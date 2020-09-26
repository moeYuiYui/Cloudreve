package onedrive

import (
	"context"
	"errors"
	"fmt"
	model "github.com/HFO4/cloudreve/models"
	"github.com/HFO4/cloudreve/pkg/cache"
	"github.com/HFO4/cloudreve/pkg/filesystem/fsctx"
	"github.com/HFO4/cloudreve/pkg/filesystem/response"
	"github.com/HFO4/cloudreve/pkg/request"
	"github.com/HFO4/cloudreve/pkg/serializer"
	"io"
	"net/url"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// Driver OneDrive 适配器
type Driver struct {
	Policy     *model.Policy
	Client     *Client
	HTTPClient request.Client
}

// List 列取项目
func (handler Driver) List(ctx context.Context, base string, recursive bool) ([]response.Object, error) {
	base = strings.TrimPrefix(base, "/")
	// 列取子项目
	objects, _ := handler.Client.ListChildren(ctx, base)

	// 获取真实的列取起始根目录
	rootPath := base
	if realBase, ok := ctx.Value(fsctx.PathCtx).(string); ok {
		rootPath = realBase
	} else {
		ctx = context.WithValue(ctx, fsctx.PathCtx, base)
	}

	// 整理结果
	res := make([]response.Object, 0, len(objects))
	for _, object := range objects {
		source := path.Join(base, object.Name)
		rel, err := filepath.Rel(rootPath, source)
		if err != nil {
			continue
		}
		res = append(res, response.Object{
			Name:         object.Name,
			RelativePath: filepath.ToSlash(rel),
			Source:       source,
			Size:         object.Size,
			IsDir:        object.Folder != nil,
			LastModify:   time.Now(),
		})
	}

	// 递归列取子目录
	if recursive {
		for _, object := range objects {
			if object.Folder != nil {
				sub, _ := handler.List(ctx, path.Join(base, object.Name), recursive)
				res = append(res, sub...)
			}
		}
	}

	return res, nil
}

// Get 获取文件
func (handler Driver) Get(ctx context.Context, path string) (response.RSCloser, error) {
	// 获取文件源地址
	downloadURL, err := handler.Source(
		ctx,
		path,
		url.URL{},
		60,
		false,
		0,
	)
	if err != nil {
		return nil, err
	}

	// 获取文件数据流
	resp, err := handler.HTTPClient.Request(
		"GET",
		downloadURL,
		nil,
		request.WithContext(ctx),
		request.WithTimeout(time.Duration(0)),
	).CheckHTTPResponse(200).GetRSCloser()
	if err != nil {
		return nil, err
	}

	resp.SetFirstFakeChunk()

	// 尝试自主获取文件大小
	if file, ok := ctx.Value(fsctx.FileModelCtx).(model.File); ok {
		resp.SetContentLength(int64(file.Size))
	}

	return resp, nil
}

// Put 将文件流保存到指定目录
func (handler Driver) Put(ctx context.Context, file io.ReadCloser, dst string, size uint64) error {
	defer file.Close()
	return handler.Client.Upload(ctx, dst, int(size), file)
}

// Delete 删除一个或多个文件，
// 返回未删除的文件，及遇到的最后一个错误
func (handler Driver) Delete(ctx context.Context, files []string) ([]string, error) {
	return handler.Client.BatchDelete(ctx, files)
}

// Thumb 获取文件缩略图
func (handler Driver) Thumb(ctx context.Context, path string) (*response.ContentResponse, error) {
	var (
		thumbSize = [2]uint{400, 300}
		ok        = false
	)
	if thumbSize, ok = ctx.Value(fsctx.ThumbSizeCtx).([2]uint); !ok {
		return nil, errors.New("无法获取缩略图尺寸设置")
	}

	res, err := handler.Client.GetThumbURL(ctx, path, thumbSize[0], thumbSize[1])
	if err != nil {
		// 如果出现异常，就清空文件的pic_info
		if file, ok := ctx.Value(fsctx.FileModelCtx).(model.File); ok {
			file.UpdatePicInfo("")
		}
	}
	return &response.ContentResponse{
		Redirect: true,
		URL:      res,
	}, err
}

// Source 获取外链URL
func (handler Driver) Source(
	ctx context.Context,
	path string,
	baseURL url.URL,
	ttl int64,
	isDownload bool,
	speed int,
) (string, error) {
	// 尝试从缓存中查找
	if cachedURL, ok := cache.Get(fmt.Sprintf("onedrive_source_%d_%s", handler.Policy.ID, path)); ok {
	    finalURL, err := handler.getFinalURL(cachedURL.(string))
		if err != nil {
	        return "", err
       }
		return finalURL, nil
	}
	// 缓存不存在，重新获取
	res, err := handler.Client.Meta(ctx, "", path)
	if err == nil {
		// 写入新的缓存
		cache.Set(
			fmt.Sprintf("onedrive_source_%d_%s", handler.Policy.ID, path),
			res.DownloadURL,
			model.GetIntSetting("onedrive_source_timeout", 1800),
		)
		finalURL, err := handler.getFinalURL(res.DownloadURL)
		if err != nil {
	        return "", err
        }
		return finalURL, nil
	}
	return "", err
}





func (handler Driver) getFinalURL(key string)(string, error){
    
    cdnURL, err := url.Parse(handler.Policy.BaseURL)
	if err != nil {
	    return "", err
    }
    
    if  cdnURL.String() == "https://login.chinacloudapi.cn/common/oauth2" {
         return key, err
    }
    if  cdnURL.String() == "https://login.microsoftonline.com/common/oauth2" {
         return key, err
    }
    if cdnURL.String() != "" {
        finalURL, err := url.Parse(key)
	    if err != nil {
	        return "", err
        }
        finalURL.Host = cdnURL.Host
     	finalURL.Scheme = cdnURL.Scheme
    	return finalURL.String(), err
    }
    
    return key, err
}






// Token 获取上传会话URL
func (handler Driver) Token(ctx context.Context, TTL int64, key string) (serializer.UploadCredential, error) {

	// 读取上下文中生成的存储路径和文件大小
	savePath, ok := ctx.Value(fsctx.SavePathCtx).(string)
	if !ok {
		return serializer.UploadCredential{}, errors.New("无法获取存储路径")
	}
	fileSize, ok := ctx.Value(fsctx.FileSizeCtx).(uint64)
	if !ok {
		return serializer.UploadCredential{}, errors.New("无法获取文件大小")
	}

	// 如果小于4MB，则由服务端中转
	if fileSize <= SmallFileSize {
		return serializer.UploadCredential{}, nil
	}

	// 生成回调地址
	siteURL := model.GetSiteURL()
	apiBaseURI, _ := url.Parse("/api/v3/callback/onedrive/finish/" + key)
	apiURL := siteURL.ResolveReference(apiBaseURI)

	uploadURL, err := handler.Client.CreateUploadSession(ctx, savePath, WithConflictBehavior("fail"))
	if err != nil {
		return serializer.UploadCredential{}, err
	}

	// 监控回调及上传
	go handler.Client.MonitorUpload(uploadURL, key, savePath, fileSize, TTL)

	return serializer.UploadCredential{
		Policy: uploadURL,
		Token:  apiURL.String(),
	}, nil
}
