#!/usr/bin/env php

<?php
echo "命令方法 ./sp setsp <存储id> <站点名称> 如: ./sp setsp 2 jane 设置站点/sites/jane";
$path = dirname(__FILE__);    
 chdir($path); 
 

//use PDO;
//use Exception;
//use PDOException;
//use InvalidArgumentException;

class Raw {
	public $map;
	public $value;
}

class Medoo
{
	public $pdo;

	protected $type;

	protected $prefix;

	protected $statement;

	protected $dsn;

	protected $logs = [];

	protected $logging = false;

	protected $debug_mode = false;

	protected $guid = 0;

	protected $errorInfo = null;

	public function __construct(array $options)
	{
		if (isset($options[ 'database_type' ]))
		{
			$this->type = strtolower($options[ 'database_type' ]);

			if ($this->type === 'mariadb')
			{
				$this->type = 'mysql';
			}
		}

		if (isset($options[ 'prefix' ]))
		{
			$this->prefix = $options[ 'prefix' ];
		}

		if (isset($options[ 'logging' ]) && is_bool($options[ 'logging' ]))
		{
			$this->logging = $options[ 'logging' ];
		}

		$option = isset($options[ 'option' ]) ? $options[ 'option' ] : [];
		$commands = (isset($options[ 'command' ]) && is_array($options[ 'command' ])) ? $options[ 'command' ] : [];

		switch ($this->type)
		{
			case 'mysql':
				// Make MySQL using standard quoted identifier
				$commands[] = 'SET SQL_MODE=ANSI_QUOTES';

				break;

			case 'mssql':
				// Keep MSSQL QUOTED_IDENTIFIER is ON for standard quoting
				$commands[] = 'SET QUOTED_IDENTIFIER ON';

				// Make ANSI_NULLS is ON for NULL value
				$commands[] = 'SET ANSI_NULLS ON';

				break;
		}

		if (isset($options[ 'pdo' ]))
		{
			if (!$options[ 'pdo' ] instanceof PDO)
			{
				throw new InvalidArgumentException('Invalid PDO object supplied');
			}

			$this->pdo = $options[ 'pdo' ];

			foreach ($commands as $value)
			{
				$this->pdo->exec($value);
			}

			return;
		}

		if (isset($options[ 'dsn' ]))
		{
			if (is_array($options[ 'dsn' ]) && isset($options[ 'dsn' ][ 'driver' ]))
			{
				$attr = $options[ 'dsn' ];
			}
			else
			{
				throw new InvalidArgumentException('Invalid DSN option supplied');
			}
		}
		else
		{
			if (
				isset($options[ 'port' ]) &&
				is_int($options[ 'port' ] * 1)
			)
			{
				$port = $options[ 'port' ];
			}

			$is_port = isset($port);

			switch ($this->type)
			{
				case 'mysql':
					$attr = [
						'driver' => 'mysql',
						'dbname' => $options[ 'database_name' ]
					];

					if (isset($options[ 'socket' ]))
					{
						$attr[ 'unix_socket' ] = $options[ 'socket' ];
					}
					else
					{
						$attr[ 'host' ] = $options[ 'server' ];

						if ($is_port)
						{
							$attr[ 'port' ] = $port;
						}
					}

					break;

				case 'pgsql':
					$attr = [
						'driver' => 'pgsql',
						'host' => $options[ 'server' ],
						'dbname' => $options[ 'database_name' ]
					];

					if ($is_port)
					{
						$attr[ 'port' ] = $port;
					}

					break;

				case 'sybase':
					$attr = [
						'driver' => 'dblib',
						'host' => $options[ 'server' ],
						'dbname' => $options[ 'database_name' ]
					];

					if ($is_port)
					{
						$attr[ 'port' ] = $port;
					}

					break;

				case 'oracle':
					$attr = [
						'driver' => 'oci',
						'dbname' => $options[ 'server' ] ?
							'//' . $options[ 'server' ] . ($is_port ? ':' . $port : ':1521') . '/' . $options[ 'database_name' ] :
							$options[ 'database_name' ]
					];

					if (isset($options[ 'charset' ]))
					{
						$attr[ 'charset' ] = $options[ 'charset' ];
					}

					break;

				case 'mssql':
					if (isset($options[ 'driver' ]) && $options[ 'driver' ] === 'dblib')
					{
						$attr = [
							'driver' => 'dblib',
							'host' => $options[ 'server' ] . ($is_port ? ':' . $port : ''),
							'dbname' => $options[ 'database_name' ]
						];

						if (isset($options[ 'appname' ]))
						{
							$attr[ 'appname' ] = $options[ 'appname' ];
						}

						if (isset($options[ 'charset' ]))
						{
							$attr[ 'charset' ] = $options[ 'charset' ];
						}
					}
					else
					{
						$attr = [
							'driver' => 'sqlsrv',
							'Server' => $options[ 'server' ] . ($is_port ? ',' . $port : ''),
							'Database' => $options[ 'database_name' ]
						];

						if (isset($options[ 'appname' ]))
						{
							$attr[ 'APP' ] = $options[ 'appname' ];
						}

						$config = [
							'ApplicationIntent',
							'AttachDBFileName',
							'Authentication',
							'ColumnEncryption',
							'ConnectionPooling',
							'Encrypt',
							'Failover_Partner',
							'KeyStoreAuthentication',
							'KeyStorePrincipalId',
							'KeyStoreSecret',
							'LoginTimeout',
							'MultipleActiveResultSets',
							'MultiSubnetFailover',
							'Scrollable',
							'TraceFile',
							'TraceOn',
							'TransactionIsolation',
							'TransparentNetworkIPResolution',
							'TrustServerCertificate',
							'WSID',
						];

						foreach ($config as $value)
						{
							$keyname = strtolower(preg_replace(['/([a-z\d])([A-Z])/', '/([^_])([A-Z][a-z])/'], '$1_$2', $value));

							if (isset($options[ $keyname ]))
							{
								$attr[ $value ] = $options[ $keyname ];
							}
						}
					}

					break;

				case 'sqlite':
					$attr = [
						'driver' => 'sqlite',
						$options[ 'database_file' ]
					];

					break;
			}
		}

		if (!isset($attr))
		{
			throw new InvalidArgumentException('Incorrect connection options');
		}

		$driver = $attr[ 'driver' ];

		if (!in_array($driver, PDO::getAvailableDrivers()))
		{
			throw new InvalidArgumentException("Unsupported PDO driver: {$driver}");
		}

		unset($attr[ 'driver' ]);

		$stack = [];

		foreach ($attr as $key => $value)
		{
			$stack[] = is_int($key) ? $value : $key . '=' . $value;
		}

		$dsn = $driver . ':' . implode(';', $stack);

		if (
			in_array($this->type, ['mysql', 'pgsql', 'sybase', 'mssql']) &&
			isset($options[ 'charset' ])
		)
		{
			$commands[] = "SET NAMES '{$options[ 'charset' ]}'" . (
				$this->type === 'mysql' && isset($options[ 'collation' ]) ?
				" COLLATE '{$options[ 'collation' ]}'" : ''
			);
		}

		$this->dsn = $dsn;

		try {
			$this->pdo = new PDO(
				$dsn,
				isset($options[ 'username' ]) ? $options[ 'username' ] : null,
				isset($options[ 'password' ]) ? $options[ 'password' ] : null,
				$option
			);

			foreach ($commands as $value)
			{
				$this->pdo->exec($value);
			}
		}
		catch (PDOException $e) {
			throw new PDOException($e->getMessage());
		}
	}

	public function query($query, $map = [])
	{
		$raw = $this->raw($query, $map);

		$query = $this->buildRaw($raw, $map);

		return $this->exec($query, $map);
	}

	public function exec($query, $map = [])
	{
		$this->statement = null;

		if ($this->debug_mode)
		{
			echo $this->generate($query, $map);

			$this->debug_mode = false;

			return false;
		}

		if ($this->logging)
		{
			$this->logs[] = [$query, $map];
		}
		else
		{
			$this->logs = [[$query, $map]];
		}

		$statement = $this->pdo->prepare($query);

		if (!$statement)
		{
			$this->errorInfo = $this->pdo->errorInfo();
			$this->statement = null;

			return false;
		}

		$this->statement = $statement;

		foreach ($map as $key => $value)
		{
			$statement->bindValue($key, $value[ 0 ], $value[ 1 ]);
		}

		$execute = $statement->execute();

		$this->errorInfo = $statement->errorInfo();

		if (!$execute)
		{
			$this->statement = null;
		}

		return $statement;
	}

	protected function generate($query, $map)
	{
		$identifier = [
			'mysql' => '`$1`',
			'mssql' => '[$1]'
		];

		$query = preg_replace(
			'/"([a-zA-Z0-9_]+)"/i',
			isset($identifier[ $this->type ]) ?  $identifier[ $this->type ] : '"$1"',
			$query
		);

		foreach ($map as $key => $value)
		{
			if ($value[ 1 ] === PDO::PARAM_STR)
			{
				$replace = $this->quote($value[ 0 ]);
			}
			elseif ($value[ 1 ] === PDO::PARAM_NULL)
			{
				$replace = 'NULL';
			}
			elseif ($value[ 1 ] === PDO::PARAM_LOB)
			{
				$replace = '{LOB_DATA}';
			}
			else
			{
				$replace = $value[ 0 ];
			}

			$query = str_replace($key, $replace, $query);
		}

		return $query;
	}

	public static function raw($string, $map = [])
	{
		$raw = new Raw();

		$raw->map = $map;
		$raw->value = $string;

		return $raw;
	}

	protected function isRaw($object)
	{
		return $object instanceof Raw;
	}

	protected function buildRaw($raw, &$map)
	{
		if (!$this->isRaw($raw))
		{
			return false;
		}

		$query = preg_replace_callback(
			'/(([`\']).*?)?((FROM|TABLE|INTO|UPDATE|JOIN)\s*)?\<(([a-zA-Z0-9_]+)(\.[a-zA-Z0-9_]+)?)\>(.*?\2)?/i',
			function ($matches)
			{
				if (!empty($matches[ 2 ]) && isset($matches[ 8 ]))
				{
					return $matches[ 0 ];
				}

				if (!empty($matches[ 4 ]))
				{
					return $matches[ 1 ] . $matches[ 4 ] . ' ' . $this->tableQuote($matches[ 5 ]);
				}

				return $matches[ 1 ] . $this->columnQuote($matches[ 5 ]);
			},
			$raw->value);

		$raw_map = $raw->map;

		if (!empty($raw_map))
		{
			foreach ($raw_map as $key => $value)
			{
				$map[ $key ] = $this->typeMap($value, gettype($value));
			}
		}

		return $query;
	}

	public function quote($string)
	{
		return $this->pdo->quote($string);
	}

	protected function tableQuote($table)
	{
		if (!preg_match('/^[a-zA-Z0-9_]+$/i', $table))
		{
			throw new InvalidArgumentException("Incorrect table name \"$table\"");
		}

		return '"' . $this->prefix . $table . '"';
	}

	protected function mapKey()
	{
		return ':MeDoO_' . $this->guid++ . '_mEdOo';
	}

	protected function typeMap($value, $type)
	{
		$map = [
			'NULL' => PDO::PARAM_NULL,
			'integer' => PDO::PARAM_INT,
			'double' => PDO::PARAM_STR,
			'boolean' => PDO::PARAM_BOOL,
			'string' => PDO::PARAM_STR,
			'object' => PDO::PARAM_STR,
			'resource' => PDO::PARAM_LOB
		];

		if ($type === 'boolean')
		{
			$value = ($value ? '1' : '0');
		}
		elseif ($type === 'NULL')
		{
			$value = null;
		}

		return [$value, $map[ $type ]];
	}

	protected function columnQuote($string)
	{
		if (!preg_match('/^[a-zA-Z0-9_]+(\.?[a-zA-Z0-9_]+)?$/i', $string))
		{
			throw new InvalidArgumentException("Incorrect column name \"$string\"");
		}

		if (strpos($string, '.') !== false)
		{
			return '"' . $this->prefix . str_replace('.', '"."', $string) . '"';
		}

		return '"' . $string . '"';
	}

	protected function columnPush(&$columns, &$map, $root, $is_join = false)
	{
		if ($columns === '*')
		{
			return $columns;
		}

		$stack = [];

		if (is_string($columns))
		{
			$columns = [$columns];
		}

		foreach ($columns as $key => $value)
		{
			if (!is_int($key) && is_array($value) && $root && count(array_keys($columns)) === 1)
			{
				$stack[] = $this->columnQuote($key);

				$stack[] = $this->columnPush($value, $map, false, $is_join);
			}
			elseif (is_array($value))
			{
				$stack[] = $this->columnPush($value, $map, false, $is_join);
			}
			elseif (!is_int($key) && $raw = $this->buildRaw($value, $map))
			{
				preg_match('/(?<column>[a-zA-Z0-9_\.]+)(\s*\[(?<type>(String|Bool|Int|Number))\])?/i', $key, $match);

				$stack[] = $raw . ' AS ' . $this->columnQuote($match[ 'column' ]);
			}
			elseif (is_int($key) && is_string($value))
			{
				if ($is_join && strpos($value, '*') !== false)
				{
					throw new InvalidArgumentException('Cannot use table.* to select all columns while joining table');
				}

				preg_match('/(?<column>[a-zA-Z0-9_\.]+)(?:\s*\((?<alias>[a-zA-Z0-9_]+)\))?(?:\s*\[(?<type>(?:String|Bool|Int|Number|Object|JSON))\])?/i', $value, $match);

				if (!empty($match[ 'alias' ]))
				{
					$stack[] = $this->columnQuote($match[ 'column' ]) . ' AS ' . $this->columnQuote($match[ 'alias' ]);

					$columns[ $key ] = $match[ 'alias' ];

					if (!empty($match[ 'type' ]))
					{
						$columns[ $key ] .= ' [' . $match[ 'type' ] . ']';
					}
				}
				else
				{
					$stack[] = $this->columnQuote($match[ 'column' ]);
				}
			}
		}

		return implode(',', $stack);
	}

	protected function arrayQuote($array)
	{
		$stack = [];

		foreach ($array as $value)
		{
			$stack[] = is_int($value) ? $value : $this->pdo->quote($value);
		}

		return implode(',', $stack);
	}

	protected function innerConjunct($data, $map, $conjunctor, $outer_conjunctor)
	{
		$stack = [];

		foreach ($data as $value)
		{
			$stack[] = '(' . $this->dataImplode($value, $map, $conjunctor) . ')';
		}

		return implode($outer_conjunctor . ' ', $stack);
	}

	protected function dataImplode($data, &$map, $conjunctor)
	{
		$stack = [];

		foreach ($data as $key => $value)
		{
			$type = gettype($value);

			if (
				$type === 'array' &&
				preg_match("/^(AND|OR)(\s+#.*)?$/", $key, $relation_match)
			)
			{
				$relationship = $relation_match[ 1 ];

				$stack[] = $value !== array_keys(array_keys($value)) ?
					'(' . $this->dataImplode($value, $map, ' ' . $relationship) . ')' :
					'(' . $this->innerConjunct($value, $map, ' ' . $relationship, $conjunctor) . ')';

				continue;
			}

			$map_key = $this->mapKey();

			if (
				is_int($key) &&
				preg_match('/([a-zA-Z0-9_\.]+)\[(?<operator>\>\=?|\<\=?|\!?\=)\]([a-zA-Z0-9_\.]+)/i', $value, $match)
			)
			{
				$stack[] = $this->columnQuote($match[ 1 ]) . ' ' . $match[ 'operator' ] . ' ' . $this->columnQuote($match[ 3 ]);
			}
			else
			{
				preg_match('/([a-zA-Z0-9_\.]+)(\[(?<operator>\>\=?|\<\=?|\!|\<\>|\>\<|\!?~|REGEXP)\])?/i', $key, $match);
				$column = $this->columnQuote($match[ 1 ]);

				if (isset($match[ 'operator' ]))
				{
					$operator = $match[ 'operator' ];

					if (in_array($operator, ['>', '>=', '<', '<=']))
					{
						$condition = $column . ' ' . $operator . ' ';

						if (is_numeric($value))
						{
							$condition .= $map_key;
							$map[ $map_key ] = [$value, is_float($value) ? PDO::PARAM_STR : PDO::PARAM_INT];
						}
						elseif ($raw = $this->buildRaw($value, $map))
						{
							$condition .= $raw;
						}
						else
						{
							$condition .= $map_key;
							$map[ $map_key ] = [$value, PDO::PARAM_STR];
						}

						$stack[] = $condition;
					}
					elseif ($operator === '!')
					{
						switch ($type)
						{
							case 'NULL':
								$stack[] = $column . ' IS NOT NULL';
								break;

							case 'array':
								$placeholders = [];

								foreach ($value as $index => $item)
								{
									$stack_key = $map_key . $index . '_i';

									$placeholders[] = $stack_key;
									$map[ $stack_key ] = $this->typeMap($item, gettype($item));
								}

								$stack[] = $column . ' NOT IN (' . implode(', ', $placeholders) . ')';
								break;

							case 'object':
								if ($raw = $this->buildRaw($value, $map))
								{
									$stack[] = $column . ' != ' . $raw;
								}
								break;

							case 'integer':
							case 'double':
							case 'boolean':
							case 'string':
								$stack[] = $column . ' != ' . $map_key;
								$map[ $map_key ] = $this->typeMap($value, $type);
								break;
						}
					}
					elseif ($operator === '~' || $operator === '!~')
					{
						if ($type !== 'array')
						{
							$value = [ $value ];
						}

						$connector = ' OR ';
						$data = array_values($value);

						if (is_array($data[ 0 ]))
						{
							if (isset($value[ 'AND' ]) || isset($value[ 'OR' ]))
							{
								$connector = ' ' . array_keys($value)[ 0 ] . ' ';
								$value = $data[ 0 ];
							}
						}

						$like_clauses = [];

						foreach ($value as $index => $item)
						{
							$item = strval($item);

							if (!preg_match('/(\[.+\]|[\*\?\!\%#^-_]|%.+|.+%)/', $item))
							{
								$item = '%' . $item . '%';
							}

							$like_clauses[] = $column . ($operator === '!~' ? ' NOT' : '') . ' LIKE ' . $map_key . 'L' . $index;
							$map[ $map_key . 'L' . $index ] = [$item, PDO::PARAM_STR];
						}

						$stack[] = '(' . implode($connector, $like_clauses) . ')';
					}
					elseif ($operator === '<>' || $operator === '><')
					{
						if ($type === 'array')
						{
							if ($operator === '><')
							{
								$column .= ' NOT';
							}

							$stack[] = '(' . $column . ' BETWEEN ' . $map_key . 'a AND ' . $map_key . 'b)';

							$data_type = (is_numeric($value[ 0 ]) && is_numeric($value[ 1 ])) ? PDO::PARAM_INT : PDO::PARAM_STR;

							$map[ $map_key . 'a' ] = [$value[ 0 ], $data_type];
							$map[ $map_key . 'b' ] = [$value[ 1 ], $data_type];
						}
					}
					elseif ($operator === 'REGEXP')
					{
						$stack[] = $column . ' REGEXP ' . $map_key;
						$map[ $map_key ] = [$value, PDO::PARAM_STR];
					}
				}
				else
				{
					switch ($type)
					{
						case 'NULL':
							$stack[] = $column . ' IS NULL';
							break;

						case 'array':
							$placeholders = [];

							foreach ($value as $index => $item)
							{
								$stack_key = $map_key . $index . '_i';

								$placeholders[] = $stack_key;
								$map[ $stack_key ] = $this->typeMap($item, gettype($item));
							}

							$stack[] = $column . ' IN (' . implode(', ', $placeholders) . ')';
							break;

						case 'object':
							if ($raw = $this->buildRaw($value, $map))
							{
								$stack[] = $column . ' = ' . $raw;
							}
							break;

						case 'integer':
						case 'double':
						case 'boolean':
						case 'string':
							$stack[] = $column . ' = ' . $map_key;
							$map[ $map_key ] = $this->typeMap($value, $type);
							break;
					}
				}
			}
		}

		return implode($conjunctor . ' ', $stack);
	}

	protected function whereClause($where, &$map)
	{
		$where_clause = '';

		if (is_array($where))
		{
			$where_keys = array_keys($where);

			$conditions = array_diff_key($where, array_flip(
				['GROUP', 'ORDER', 'HAVING', 'LIMIT', 'LIKE', 'MATCH']
			));

			if (!empty($conditions))
			{
				$where_clause = ' WHERE ' . $this->dataImplode($conditions, $map, ' AND');
			}

			if (isset($where[ 'MATCH' ]) && $this->type === 'mysql')
			{
				$MATCH = $where[ 'MATCH' ];

				if (is_array($MATCH) && isset($MATCH[ 'columns' ], $MATCH[ 'keyword' ]))
				{
					$mode = '';

					$mode_array = [
						'natural' => 'IN NATURAL LANGUAGE MODE',
						'natural+query' => 'IN NATURAL LANGUAGE MODE WITH QUERY EXPANSION',
						'boolean' => 'IN BOOLEAN MODE',
						'query' => 'WITH QUERY EXPANSION'
					];

					if (isset($MATCH[ 'mode' ], $mode_array[ $MATCH[ 'mode' ] ]))
					{
						$mode = ' ' . $mode_array[ $MATCH[ 'mode' ] ];
					}

					$columns = implode(', ', array_map([$this, 'columnQuote'], $MATCH[ 'columns' ]));
					$map_key = $this->mapKey();
					$map[ $map_key ] = [$MATCH[ 'keyword' ], PDO::PARAM_STR];

					$where_clause .= ($where_clause !== '' ? ' AND ' : ' WHERE') . ' MATCH (' . $columns . ') AGAINST (' . $map_key . $mode . ')';
				}
			}

			if (isset($where[ 'GROUP' ]))
			{
				$GROUP = $where[ 'GROUP' ];

				if (is_array($GROUP))
				{
					$stack = [];

					foreach ($GROUP as $column => $value)
					{
						$stack[] = $this->columnQuote($value);
					}

					$where_clause .= ' GROUP BY ' . implode(',', $stack);
				}
				elseif ($raw = $this->buildRaw($GROUP, $map))
				{
					$where_clause .= ' GROUP BY ' . $raw;
				}
				else
				{
					$where_clause .= ' GROUP BY ' . $this->columnQuote($GROUP);
				}

				if (isset($where[ 'HAVING' ]))
				{
					if ($raw = $this->buildRaw($where[ 'HAVING' ], $map))
					{
						$where_clause .= ' HAVING ' . $raw;
					}
					else
					{
						$where_clause .= ' HAVING ' . $this->dataImplode($where[ 'HAVING' ], $map, ' AND');
					}
				}
			}

			if (isset($where[ 'ORDER' ]))
			{
				$ORDER = $where[ 'ORDER' ];

				if (is_array($ORDER))
				{
					$stack = [];

					foreach ($ORDER as $column => $value)
					{
						if (is_array($value))
						{
							$stack[] = 'FIELD(' . $this->columnQuote($column) . ', ' . $this->arrayQuote($value) . ')';
						}
						elseif ($value === 'ASC' || $value === 'DESC')
						{
							$stack[] = $this->columnQuote($column) . ' ' . $value;
						}
						elseif (is_int($column))
						{
							$stack[] = $this->columnQuote($value);
						}
					}

					$where_clause .= ' ORDER BY ' . implode(',', $stack);
				}
				elseif ($raw = $this->buildRaw($ORDER, $map))
				{
					$where_clause .= ' ORDER BY ' . $raw;	
				}
				else
				{
					$where_clause .= ' ORDER BY ' . $this->columnQuote($ORDER);
				}

				if (
					isset($where[ 'LIMIT' ]) &&
					in_array($this->type, ['oracle', 'mssql'])
				)
				{
					$LIMIT = $where[ 'LIMIT' ];

					if (is_numeric($LIMIT))
					{
						$LIMIT = [0, $LIMIT];
					}
					
					if (
						is_array($LIMIT) &&
						is_numeric($LIMIT[ 0 ]) &&
						is_numeric($LIMIT[ 1 ])
					)
					{
						$where_clause .= ' OFFSET ' . $LIMIT[ 0 ] . ' ROWS FETCH NEXT ' . $LIMIT[ 1 ] . ' ROWS ONLY';
					}
				}
			}

			if (isset($where[ 'LIMIT' ]) && !in_array($this->type, ['oracle', 'mssql']))
			{
				$LIMIT = $where[ 'LIMIT' ];

				if (is_numeric($LIMIT))
				{
					$where_clause .= ' LIMIT ' . $LIMIT;
				}
				elseif (
					is_array($LIMIT) &&
					is_numeric($LIMIT[ 0 ]) &&
					is_numeric($LIMIT[ 1 ])
				)
				{
					$where_clause .= ' LIMIT ' . $LIMIT[ 1 ] . ' OFFSET ' . $LIMIT[ 0 ];
				}
			}
		}
		elseif ($raw = $this->buildRaw($where, $map))
		{
			$where_clause .= ' ' . $raw;
		}

		return $where_clause;
	}

	protected function selectContext($table, &$map, $join, &$columns = null, $where = null, $column_fn = null)
	{
		preg_match('/(?<table>[a-zA-Z0-9_]+)\s*\((?<alias>[a-zA-Z0-9_]+)\)/i', $table, $table_match);

		if (isset($table_match[ 'table' ], $table_match[ 'alias' ]))
		{
			$table = $this->tableQuote($table_match[ 'table' ]);

			$table_query = $table . ' AS ' . $this->tableQuote($table_match[ 'alias' ]);
		}
		else
		{
			$table = $this->tableQuote($table);

			$table_query = $table;
		}

		$is_join = false;
		$join_key = is_array($join) ? array_keys($join) : null;

		if (
			isset($join_key[ 0 ]) &&
			strpos($join_key[ 0 ], '[') === 0
		)
		{
			$is_join = true;
			$table_query .= ' ' . $this->buildJoin($table, $join);
		}
		else
		{
			if (is_null($columns))
			{
				if (
					!is_null($where) ||
					(is_array($join) && isset($column_fn))
				)
				{
					$where = $join;
					$columns = null;
				}
				else
				{
					$where = null;
					$columns = $join;
				}
			}
			else
			{
				$where = $columns;
				$columns = $join;
			}
		}

		if (isset($column_fn))
		{
			if ($column_fn === 1)
			{
				$column = '1';

				if (is_null($where))
				{
					$where = $columns;
				}
			}
			elseif ($raw = $this->buildRaw($column_fn, $map))
			{
				$column = $raw;
			}
			else
			{
				if (empty($columns) || $this->isRaw($columns))
				{
					$columns = '*';
					$where = $join;
				}

				$column = $column_fn . '(' . $this->columnPush($columns, $map, true) . ')';
			}
		}
		else
		{
			$column = $this->columnPush($columns, $map, true, $is_join);
		}

		return 'SELECT ' . $column . ' FROM ' . $table_query . $this->whereClause($where, $map);
	}

	protected function buildJoin($table, $join)
	{
		$table_join = [];

		$join_array = [
			'>' => 'LEFT',
			'<' => 'RIGHT',
			'<>' => 'FULL',
			'><' => 'INNER'
		];

		foreach($join as $sub_table => $relation)
		{
			preg_match('/(\[(?<join>\<\>?|\>\<?)\])?(?<table>[a-zA-Z0-9_]+)\s?(\((?<alias>[a-zA-Z0-9_]+)\))?/', $sub_table, $match);

			if ($match[ 'join' ] !== '' && $match[ 'table' ] !== '')
			{
				if (is_string($relation))
				{
					$relation = 'USING ("' . $relation . '")';
				}

				if (is_array($relation))
				{
					// For ['column1', 'column2']
					if (isset($relation[ 0 ]))
					{
						$relation = 'USING ("' . implode('", "', $relation) . '")';
					}
					else
					{
						$joins = [];

						foreach ($relation as $key => $value)
						{
							$joins[] = (
								strpos($key, '.') > 0 ?
									// For ['tableB.column' => 'column']
									$this->columnQuote($key) :

									// For ['column1' => 'column2']
									$table . '."' . $key . '"'
							) .
							' = ' .
							$this->tableQuote(isset($match[ 'alias' ]) ? $match[ 'alias' ] : $match[ 'table' ]) . '."' . $value . '"';
						}

						$relation = 'ON ' . implode(' AND ', $joins);
					}
				}

				$table_name = $this->tableQuote($match[ 'table' ]) . ' ';

				if (isset($match[ 'alias' ]))
				{
					$table_name .= 'AS ' . $this->tableQuote($match[ 'alias' ]) . ' ';
				}

				$table_join[] = $join_array[ $match[ 'join' ] ] . ' JOIN ' . $table_name . $relation;
			}
		}

		return implode(' ', $table_join);
	}

	protected function columnMap($columns, &$stack, $root)
	{
		if ($columns === '*')
		{
			return $stack;
		}

		foreach ($columns as $key => $value)
		{
			if (is_int($key))
			{
				preg_match('/([a-zA-Z0-9_]+\.)?(?<column>[a-zA-Z0-9_]+)(?:\s*\((?<alias>[a-zA-Z0-9_]+)\))?(?:\s*\[(?<type>(?:String|Bool|Int|Number|Object|JSON))\])?/i', $value, $key_match);

				$column_key = !empty($key_match[ 'alias' ]) ?
					$key_match[ 'alias' ] :
					$key_match[ 'column' ];

				if (isset($key_match[ 'type' ]))
				{
					$stack[ $value ] = [$column_key, $key_match[ 'type' ]];
				}
				else
				{
					$stack[ $value ] = [$column_key, 'String'];
				}
			}
			elseif ($this->isRaw($value))
			{
				preg_match('/([a-zA-Z0-9_]+\.)?(?<column>[a-zA-Z0-9_]+)(\s*\[(?<type>(String|Bool|Int|Number))\])?/i', $key, $key_match);

				$column_key = $key_match[ 'column' ];

				if (isset($key_match[ 'type' ]))
				{
					$stack[ $key ] = [$column_key, $key_match[ 'type' ]];
				}
				else
				{
					$stack[ $key ] = [$column_key, 'String'];
				}
			}
			elseif (!is_int($key) && is_array($value))
			{
				if ($root && count(array_keys($columns)) === 1)
				{
					$stack[ $key ] = [$key, 'String'];
				}

				$this->columnMap($value, $stack, false);
			}
		}

		return $stack;
	}

	protected function dataMap($data, $columns, $column_map, &$stack, $root, &$result)
	{
		if ($root)
		{
			$columns_key = array_keys($columns);

			if (count($columns_key) === 1 && is_array($columns[$columns_key[0]]))
			{
				$index_key = array_keys($columns)[0];
				$data_key = preg_replace("/^[a-zA-Z0-9_]+\./i", "", $index_key);

				$current_stack = [];

				foreach ($data as $item)
				{
					$this->dataMap($data, $columns[ $index_key ], $column_map, $current_stack, false, $result);

					$index = $data[ $data_key ];

					$result[ $index ] = $current_stack;
				}
			}
			else
			{
				$current_stack = [];
				
				$this->dataMap($data, $columns, $column_map, $current_stack, false, $result);

				$result[] = $current_stack;
			}

			return;
		}

		foreach ($columns as $key => $value)
		{
			$isRaw = $this->isRaw($value);

			if (is_int($key) || $isRaw)
			{
				$map = $column_map[ $isRaw ? $key : $value ];

				$column_key = $map[ 0 ];

				$item = $data[ $column_key ];

				if (isset($map[ 1 ]))
				{
					if ($isRaw && in_array($map[ 1 ], ['Object', 'JSON']))
					{
						continue;
					}

					if (is_null($item))
					{
						$stack[ $column_key ] = null;
						continue;
					}

					switch ($map[ 1 ])
					{
						case 'Number':
							$stack[ $column_key ] = (double) $item;
							break;

						case 'Int':
							$stack[ $column_key ] = (int) $item;
							break;

						case 'Bool':
							$stack[ $column_key ] = (bool) $item;
							break;

						case 'Object':
							$stack[ $column_key ] = unserialize($item);
							break;

						case 'JSON':
							$stack[ $column_key ] = json_decode($item, true);
							break;

						case 'String':
							$stack[ $column_key ] = $item;
							break;
					}
				}
				else
				{
					$stack[ $column_key ] = $item;
				}
			}
			else
			{
				$current_stack = [];

				$this->dataMap($data, $value, $column_map, $current_stack, false, $result);

				$stack[ $key ] = $current_stack;
			}
		}
	}

	public function create($table, $columns, $options = null)
	{
		$stack = [];

		$tableName = $this->prefix . $table;

		foreach ($columns as $name => $definition)
		{
			if (is_int($name))
			{
				$stack[] = preg_replace('/\<([a-zA-Z0-9_]+)\>/i', '"$1"', $definition);
			}
			elseif (is_array($definition))
			{
				$stack[] = $name . ' ' . implode(' ', $definition);
			}
			elseif (is_string($definition))
			{
				$stack[] = $name . ' ' . $this->query($definition);
			}
		}

		$table_option = '';

		if (is_array($options))
		{
			$option_stack = [];

			foreach ($options as $key => $value)
			{
				if (is_string($value) || is_int($value))
				{
					$option_stack[] = "$key = $value";
				}
			}

			$table_option = ' ' . implode(', ', $option_stack);
		}
		elseif (is_string($options))
		{
			$table_option = ' ' . $options;
		}

		return $this->exec("CREATE TABLE IF NOT EXISTS $tableName (" . implode(', ', $stack) . ")$table_option");
	}

	public function drop($table)
	{
		$tableName = $this->prefix . $table;

		return $this->exec("DROP TABLE IF EXISTS $tableName");
	}

	public function select($table, $join, $columns = null, $where = null)
	{
		$map = [];
		$result = [];
		$column_map = [];

		$index = 0;

		$column = $where === null ? $join : $columns;

		$is_single = (is_string($column) && $column !== '*');

		$query = $this->exec($this->selectContext($table, $map, $join, $columns, $where), $map);

		$this->columnMap($columns, $column_map, true);

		if (!$this->statement)
		{
			return false;
		}

		if ($columns === '*')
		{
			return $query->fetchAll(PDO::FETCH_ASSOC);
		}

		while ($data = $query->fetch(PDO::FETCH_ASSOC))
		{
			$current_stack = [];

			$this->dataMap($data, $columns, $column_map, $current_stack, true, $result);
		}

		if ($is_single)
		{
			$single_result = [];
			$result_key = $column_map[ $column ][ 0 ];

			foreach ($result as $item)
			{
				$single_result[] = $item[ $result_key ];
			}

			return $single_result;
		}

		return $result;
	}

	public function insert($table, $datas)
	{
		$stack = [];
		$columns = [];
		$fields = [];
		$map = [];

		if (!isset($datas[ 0 ]))
		{
			$datas = [$datas];
		}

		foreach ($datas as $data)
		{
			foreach ($data as $key => $value)
			{
				$columns[] = $key;
			}
		}

		$columns = array_unique($columns);

		foreach ($datas as $data)
		{
			$values = [];

			foreach ($columns as $key)
			{
				if ($raw = $this->buildRaw($data[ $key ], $map))
				{
					$values[] = $raw;
					continue;
				}

				$map_key = $this->mapKey();

				$values[] = $map_key;

				if (!isset($data[ $key ]))
				{
					$map[ $map_key ] = [null, PDO::PARAM_NULL];
				}
				else
				{
					$value = $data[ $key ];

					$type = gettype($value);

					switch ($type)
					{
						case 'array':
							$map[ $map_key ] = [
								strpos($key, '[JSON]') === strlen($key) - 6 ?
									json_encode($value) :
									serialize($value),
								PDO::PARAM_STR
							];
							break;

						case 'object':
							$value = serialize($value);

						case 'NULL':
						case 'resource':
						case 'boolean':
						case 'integer':
						case 'double':
						case 'string':
							$map[ $map_key ] = $this->typeMap($value, $type);
							break;
					}
				}
			}

			$stack[] = '(' . implode(', ', $values) . ')';
		}

		foreach ($columns as $key)
		{
			$fields[] = $this->columnQuote(preg_replace("/(\s*\[JSON\]$)/i", '', $key));
		}

		return $this->exec('INSERT INTO ' . $this->tableQuote($table) . ' (' . implode(', ', $fields) . ') VALUES ' . implode(', ', $stack), $map);
	}

	public function update($table, $data, $where = null)
	{
		$fields = [];
		$map = [];

		foreach ($data as $key => $value)
		{
			$column = $this->columnQuote(preg_replace("/(\s*\[(JSON|\+|\-|\*|\/)\]$)/i", '', $key));

			if ($raw = $this->buildRaw($value, $map))
			{
				$fields[] = $column . ' = ' . $raw;
				continue;
			}

			$map_key = $this->mapKey();

			preg_match('/(?<column>[a-zA-Z0-9_]+)(\[(?<operator>\+|\-|\*|\/)\])?/i', $key, $match);

			if (isset($match[ 'operator' ]))
			{
				if (is_numeric($value))
				{
					$fields[] = $column . ' = ' . $column . ' ' . $match[ 'operator' ] . ' ' . $value;
				}
			}
			else
			{
				$fields[] = $column . ' = ' . $map_key;

				$type = gettype($value);

				switch ($type)
				{
					case 'array':
						$map[ $map_key ] = [
							strpos($key, '[JSON]') === strlen($key) - 6 ?
								json_encode($value) :
								serialize($value),
							PDO::PARAM_STR
						];
						break;

					case 'object':
						$value = serialize($value);

					case 'NULL':
					case 'resource':
					case 'boolean':
					case 'integer':
					case 'double':
					case 'string':
						$map[ $map_key ] = $this->typeMap($value, $type);
						break;
				}
			}
		}

		return $this->exec('UPDATE ' . $this->tableQuote($table) . ' SET ' . implode(', ', $fields) . $this->whereClause($where, $map), $map);
	}

	public function delete($table, $where)
	{
		$map = [];

		return $this->exec('DELETE FROM ' . $this->tableQuote($table) . $this->whereClause($where, $map), $map);
	}

	public function replace($table, $columns, $where = null)
	{
		if (!is_array($columns) || empty($columns))
		{
			return false;
		}

		$map = [];
		$stack = [];

		foreach ($columns as $column => $replacements)
		{
			if (is_array($replacements))
			{
				foreach ($replacements as $old => $new)
				{
					$map_key = $this->mapKey();

					$stack[] = $this->columnQuote($column) . ' = REPLACE(' . $this->columnQuote($column) . ', ' . $map_key . 'a, ' . $map_key . 'b)';

					$map[ $map_key . 'a' ] = [$old, PDO::PARAM_STR];
					$map[ $map_key . 'b' ] = [$new, PDO::PARAM_STR];
				}
			}
		}

		if (!empty($stack))
		{
			return $this->exec('UPDATE ' . $this->tableQuote($table) . ' SET ' . implode(', ', $stack) . $this->whereClause($where, $map), $map);
		}

		return false;
	}

	public function get($table, $join = null, $columns = null, $where = null)
	{
		$map = [];
		$result = [];
		$column_map = [];
		$current_stack = [];

		if ($where === null)
		{
			$column = $join;
			unset($columns[ 'LIMIT' ]);
		}
		else
		{
			$column = $columns;
			unset($where[ 'LIMIT' ]);
		}

		$is_single = (is_string($column) && $column !== '*');

		$query = $this->exec($this->selectContext($table, $map, $join, $columns, $where) . ' LIMIT 1', $map);

		if (!$this->statement)
		{
			return false;
		}

		$data = $query->fetchAll(PDO::FETCH_ASSOC);

		if (isset($data[ 0 ]))
		{
			if ($column === '*')
			{
				return $data[ 0 ];
			}

			$this->columnMap($columns, $column_map, true);

			$this->dataMap($data[ 0 ], $columns, $column_map, $current_stack, true, $result);

			if ($is_single)
			{
				return $result[ 0 ][ $column_map[ $column ][ 0 ] ];
			}

			return $result[ 0 ];
		}
	}

	public function has($table, $join, $where = null)
	{
		$map = [];
		$column = null;

		if ($this->type === 'mssql')
		{
			$query = $this->exec($this->selectContext($table, $map, $join, $column, $where, Medoo::raw('TOP 1 1')), $map);
		}
		else
		{
			$query = $this->exec('SELECT EXISTS(' . $this->selectContext($table, $map, $join, $column, $where, 1) . ')', $map);
		}

		if (!$this->statement)
		{
			return false;
		}

		$result = $query->fetchColumn();

		return $result === '1' || $result === 1 || $result === true;
	}

	public function rand($table, $join = null, $columns = null, $where = null)
	{
		$type = $this->type;

		$order = 'RANDOM()';

		if ($type === 'mysql')
		{
			$order = 'RAND()';
		}
		elseif ($type === 'mssql')
		{
			$order = 'NEWID()';
		}

		$order_raw = $this->raw($order);

		if ($where === null)
		{
			if ($columns === null)
			{
				$columns = [
					'ORDER'  => $order_raw
				];
			}
			else
			{
				$column = $join;
				unset($columns[ 'ORDER' ]);

				$columns[ 'ORDER' ] = $order_raw;
			}
		}
		else
		{
			unset($where[ 'ORDER' ]);

			$where[ 'ORDER' ] = $order_raw;
		}

		return $this->select($table, $join, $columns, $where);
	}

	private function aggregate($type, $table, $join = null, $column = null, $where = null)
	{
		$map = [];

		$query = $this->exec($this->selectContext($table, $map, $join, $column, $where, strtoupper($type)), $map);

		if (!$this->statement)
		{
			return false;
		}

		$number = $query->fetchColumn();

		return is_numeric($number) ? $number + 0 : $number;
	}

	public function count($table, $join = null, $column = null, $where = null)
	{
		return $this->aggregate('count', $table, $join, $column, $where);
	}

	public function avg($table, $join, $column = null, $where = null)
	{
		return $this->aggregate('avg', $table, $join, $column, $where);
	}

	public function max($table, $join, $column = null, $where = null)
	{
		return $this->aggregate('max', $table, $join, $column, $where);
	}

	public function min($table, $join, $column = null, $where = null)
	{
		return $this->aggregate('min', $table, $join, $column, $where);
	}

	public function sum($table, $join, $column = null, $where = null)
	{
		return $this->aggregate('sum', $table, $join, $column, $where);
	}

	public function action($actions)
	{
		if (is_callable($actions))
		{
			$this->pdo->beginTransaction();

			try {
				$result = $actions($this);

				if ($result === false)
				{
					$this->pdo->rollBack();
				}
				else
				{
					$this->pdo->commit();
				}
			}
			catch (Exception $e) {
				$this->pdo->rollBack();

				throw $e;
			}

			return $result;
		}

		return false;
	}

	public function id()
	{
		if ($this->statement == null)
		{
			return null;
		}

		$type = $this->type;

		if ($type === 'oracle')
		{
			return 0;
		}
		elseif ($type === 'pgsql')
		{
			return $this->pdo->query('SELECT LASTVAL()')->fetchColumn();
		}

		$lastId = $this->pdo->lastInsertId();

		if ($lastId != "0" && $lastId != "")
		{
			return $lastId;
		}

		return null;
	}

	public function debug()
	{
		$this->debug_mode = true;

		return $this;
	}

	public function error()
	{
		return $this->errorInfo;
	}

	public function last()
	{
		$log = end($this->logs);

		return $this->generate($log[ 0 ], $log[ 1 ]);
	}

	public function log()
	{
		return array_map(function ($log)
			{
				return $this->generate($log[ 0 ], $log[ 1 ]);
			},
			$this->logs
		);
	}

	public function info()
	{
		$output = [
			'server' => 'SERVER_INFO',
			'driver' => 'DRIVER_NAME',
			'client' => 'CLIENT_VERSION',
			'version' => 'SERVER_VERSION',
			'connection' => 'CONNECTION_STATUS'
		];

		foreach ($output as $key => $value)
		{
			$output[ $key ] = @$this->pdo->getAttribute(constant('PDO::ATTR_' . $value));
		}

		$output[ 'dsn' ] = $this->dsn;

		return $output;
	}
}





 //echo "欢迎使用sp站点获取工具\n";
// echo "使用方法./sp id 站点字母,   如 ./sp 2 jane 就困设置id2为sharepoint 站点";
 class fetch
{
    public static $headers = 'User-Agent:Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36';
    public static $cookies;
    public static $curl_opt;
    public static $proxy;

    public static $max_connect = 20;

    public static function init($opt = array())
    {
        self::$curl_opt = array(
            CURLOPT_RETURNTRANSFER => 1, //true, $head 有请求的返回值
            CURLOPT_BINARYTRANSFER => true, //返回原生的Raw输出
            CURLOPT_HEADER => true, //启用时会将头文件的信息作为数据流输出。
            CURLOPT_FAILONERROR => true, //显示HTTP状态码，默认行为是忽略编号小于等于400的HTTP信息。
            CURLOPT_AUTOREFERER => true, //当根据Location:重定向时，自动设置header中的Referer:信息。
            CURLOPT_FOLLOWLOCATION => false, //跳转
            CURLOPT_CONNECTTIMEOUT => 3, //在发起连接前等待的时间，如果设置为0，则无限等待。
            CURLOPT_TIMEOUT => 25, //设置cURL允许执行的最长秒数。
            CURLOPT_ENCODING => 'gzip,deflate',
            CURLOPT_SSL_VERIFYHOST => false,
            CURLOPT_SSL_VERIFYPEER => false,
        );
        foreach ($opt as $k => $v) {
            self::$curl_opt[$k] = $v;
        }
    }

    /**
     * fetch::get('http://www.google.com/');
     * fetch::post('http://www.google.com/', array('name'=>'foo'));.
     */
    public static function __callStatic($method, $args)
    {
        if (is_null(self::$curl_opt)) {
            self::init();
        }
        @list($request, $post_data, $callback) = $args;
        if (is_callable($post_data)) {
            $callback = $post_data;
            $post_data = null;
        }

        //single_curl
        if (is_string($request) || !empty($request['url'])) {
            $request = self::bulid_request($request, $method, $post_data, $callback);

            return self::single_curl($request);
        } elseif (is_array($request)) {
            //rolling_curl
            foreach ($request as $k => $r) {
                $requests[$k] = self::bulid_request($r, $method, $post_data, $callback);
            }

            return self::rolling_curl($requests);
        }
    }

    private static function bulid_request($request, $method = 'GET', $post_data = null, $callback = null)
    {
        //url
        if (is_string($request)) {
            $request = array('url' => $request);
        }
        empty($request['method']) && $request['method'] = $method;
        empty($request['post_data']) && $request['post_data'] = $post_data;
        empty($request['callback']) && $request['callback'] = $callback;

        return $request;
    }

    private static function bulid_ch(&$request)
    {
        // url
        $ch = curl_init($request['url']);
        // curl_opt
        $curl_opt = empty($request['curl_opt']) ? array() : $request['curl_opt'];
        $curl_opt = $curl_opt + (array) self::$curl_opt;
        // method
        $curl_opt[CURLOPT_CUSTOMREQUEST] = strtoupper($request['method']);
        // post_data
        if (!empty($request['post_data'])) {
            $curl_opt[CURLOPT_POST] = true;
            $curl_opt[CURLOPT_POSTFIELDS] = $request['post_data'];
        }
        // header
        $headers = @self::bulid_request_header($request['headers'], $cookies);
        $curl_opt[CURLOPT_HTTPHEADER] = $headers;

        // cookies
        $request['cookies'] = empty($request['cookies']) ? fetch::$cookies : $request['cookies'];
        $cookies = empty($request['cookies']) ? $cookies : self::cookies_arr2str($request['cookies']);
        if (!empty($cookies)) {
            $curl_opt[CURLOPT_COOKIE] = $cookies;
        }

        //proxy
        $proxy = empty($request['proxy']) ? self::$proxy : $request['proxy'];
        if (!empty($proxy)) {
            $curl_opt[CURLOPT_PROXY] = $proxy;
        }

        //setopt
        curl_setopt_array($ch, $curl_opt);

        $request['curl_opt'] = $curl_opt;
        $request['ch'] = $ch;

        return $ch;
    }

    private static function response($raw, $ch)
    {
        $response = (object) curl_getinfo($ch);
        $response->raw = $raw;
        //$raw = fetch::iconv($raw, $response->content_type);
        $response->headers = substr($raw, 0, $response->header_size);
        $response->cookies = fetch::get_respone_cookies($response->headers);
        fetch::$cookies = array_merge((array) fetch::$cookies, $response->cookies);
        $response->content = substr($raw, $response->header_size);

        return $response;
    }

    private static function single_curl($request)
    {
        $ch = self::bulid_ch($request);
        $raw = curl_exec($ch);
        $response = self::response($raw, $ch);
        curl_close($ch);
        if (is_callable($request['callback'])) {
            call_user_func($request['callback'], $response, $request);
        }

        return $response;
    }

    private static function rolling_curl($requests)
    {
        $master = curl_multi_init();
        $map = array();
        // start the first batch of requests
        do {
            $k = key($requests);
            $request = current($requests);
            next($requests);
            $ch = self::bulid_ch($request);
            curl_multi_add_handle($master, $ch);
            $key = (string) $ch;
            $map[$key] = array($k, $request['callback']);
        } while (count($map) < self::$max_connect && count($map) < count($requests));

        do {
            while (($execrun = curl_multi_exec($master, $running)) == CURLM_CALL_MULTI_PERFORM);
            if ($execrun != CURLM_OK) {
                break;
            }

            // a request was just completed -- find out which one
            while ($done = curl_multi_info_read($master)) {
                $key = (string) $done['handle'];

                list($k, $callback) = $map[$key];

                // get the info and content returned on the request
                $raw = curl_multi_getcontent($done['handle']);
                $response = self::response($raw, $done['handle']);
                $responses[$k] = $response;

                // send the return values to the callback function.
                if (is_callable($callback)) {
                    $key = (string) $done['handle'];
                    unset($map[$key]);
                    call_user_func($callback, $response, $requests[$k], $k);
                }

                // start a new request (it's important to do this before removing the old one)
                $k = key($requests);
                if (!empty($k)) {
                    $k = key($requests);
                    $request = current($requests);
                    next($requests);
                    $ch = self::bulid_ch($request);
                    curl_multi_add_handle($master, $ch);
                    $key = (string) $ch;
                    $map[$key] = array($k, $request['callback']);
                    curl_multi_exec($master, $running);
                }

                // remove the curl handle that just completed
                curl_multi_remove_handle($master, $done['handle']);
            }

            // Block for data in / output; error handling is done by curl_multi_exec
            if ($running) {
                curl_multi_select($master, 10);
            }
        } while ($running);

        return $responses;
    }

    private static function bulid_request_header($headers, &$cookies)
    {
        if (is_array($headers)) {
            $headers = join(PHP_EOL, $headers);
        }
        if (is_array(self::$headers)) {
            self::$headers = join(PHP_EOL, self::$headers);
        }
        $headers = self::$headers.PHP_EOL.$headers;

        foreach (explode(PHP_EOL, $headers) as $k => $v) {
            @list($k, $v) = explode(':', $v, 2);
            if (empty($k) || empty($v)) {
                continue;
            }
            $k = implode('-', array_map('ucfirst', explode('-', $k)));
            $tmp[$k] = $v;
        }

        foreach ((array) $tmp as $k => $v) {
            if ($k == 'Cookie') {
                $cookies = $v;
            } else {
                $return[] = $k.':'.$v;
            }
        }

        return (array) $return;
    }

    public static function iconv(&$raw, $content_type)
    {
        @list($tmp, $charset) = explode('CHARSET=', strtoupper($content_type));

        if (empty($charset) && stripos($content_type, 'html') > 0) {
            preg_match('@\<meta.+?charset=([\w]+)[\'|\"]@i', $raw, $matches);
            $charset = empty($matches[1]) ? null : $matches[1];
        }

        return empty($charset) ? $raw : iconv($charset, 'UTF-8//IGNORE', $raw);
    }

    public static function get_respone_cookies($raw)
    {
        $cookies = array();
        if (strpos($raw, PHP_EOL) != false) {
            $lines = explode(PHP_EOL, $raw);
        } elseif (strpos($raw, "\r\n") != false) {
            $lines = explode("\r\n", $raw);
        } elseif (strpos($raw, '\r\n') != false) {
            $lines = explode('\r\n', $raw);
        }

        foreach ((array) $lines as $line) {
            if (substr($line, 0, 11) == 'Set-Cookie:') {
                list($k, $v) = explode('=', substr($line, 11), 2);
                list($v, $tmp) = explode(';', $v);
                $cookies[trim($k)] = trim($v);
            }
        }

        return $cookies;
    }

    public static function cookies_arr2str($arr)
    {
        $str = '';
        foreach ((array) $arr as $k => $v) {
            $str .= $k.'='.$v.'; ';
        }

        return $str;
    }
}

function get_accesstoken($refresh_token,$client_id,$client_secret,$redirect_uri)
{
    
    $request['url'] = 'https://login.chinacloudapi.cn/common/oauth2/v2.0/token';
    $request['post_data'] = "client_id={$client_id}&redirect_uri={$redirect_uri}&client_secret={$client_secret}&refresh_token={$refresh_token}&grant_type=refresh_token";
    $request['headers'] = 'Content-Type: application/x-www-form-urlencoded';
    $resp = fetch::post($request);
    $data = json_decode($resp->content, true);

  return ($data["access_token"]);

    
}



   //获取站点id  github.com/742481030/oneindex/oneindex
    function get_siteidbyname($sitename, $access_token,$apiurl)
   {
       $request['headers'] = "Authorization: bearer {$access_token}".PHP_EOL.'Content-Type: application/json'.PHP_EOL;
       $request['url'] =$apiurl. '/sites/root';
       $resp = fetch::get($request);
       $data = json_decode($resp->content, true);
     $hostname = $data['siteCollection']['hostname'];

       $getsiteid = $apiurl.'/sites/'.$hostname.':sites/'.$sitename;
       $request['url'] = $getsiteid;
       $respp = fetch::get($request);
       $datass = json_decode($respp->content, true);
if ($datass['id']!="")
       {return $apiurl.'/sites/'.$datass['id'].'/drive/';}


       else{
echo "商业版没有站点";
echo "搜索教育版中.............\n";

        $getsiteid = $apiurl.'/sites/'.$hostname.':/teams/'.$sitename;
        $request['url'] = $getsiteid;
        $respp = fetch::get($request);
        $datass = json_decode($respp->content, true);
        if ($datass['id']!="")
        {return $apiurl.'/sites/'.$datass['id'].'/drive/';
        }
        else{
            echo"没有站点";
        }
       }
   }




function init(){
if(!file_exists('./cloudreve'))
{die("没有找到cloudreve,请放到同一目录");}
//系统初始化
$config=parse_ini_file("./conf.ini",true);

if ($config["Database"]["Type"]=="mysql")
{
echo "当前使用mysql数据库";
 return $database = new medoo([
    'database_type' => 'mysql',
    'database_name' => $config["Database"]["Name"],
    'server' => $config["Database"]["Host"],
    'username' => $config["Database"]["User"],
    'password' => $config["Database"]["Password"],
    'charset' => 'utf8'
]);
}
else{
    echo "当前使用sqllite数据库,建议更换mysql";

    if (file_exists("./cloudreve.db"))
    {
      
   return     $database = new medoo([
            'database_type' => 'sqlite',
            'database_file' => './cloudreve.db'
        ]);
       
       
    
    }





}}







   

class sp{



   static function setsp ($id,$b){

    $database=init();
$row = $database->select("policies", 
   '*'

, [
    "type[=]" =>"onedrive",
    "id[=]" =>$id,
    
]);

if (empty($row)){
    exit("没有存储策略\n");
}
$row=$row[0];

       $refresh_token=$row["access_key"];
   $client_id=$row["bucket_name"];
      $client_secret=$row["secret_key"];
      $redirect_uri=json_decode($row["options"],true)["od_redirect"];//["od_redirect"];
$baseurl=$row["base_url"];
   $serverurl=$row["server"];
if( parse_url( $serverurl,PHP_URL_HOST)=="microsoftgraph.chinacloudapi.cn" ||$baseurl=="login.chinacloudapi.cn")


{
    echo'当前世纪互联onedrive
    ';
    $serverurl='https://microsoftgraph.chinacloudapi.cn/v1.0';


}else{
    echo'当前国际版onedrive
';
    $serverurl='https://graph.microsoft.com/v1.0';

}
 $cc=get_accesstoken($refresh_token,$client_id,$client_secret,$redirect_uri);

$siteid= get_siteidbyname($b, $cc,$serverurl);
   

if($siteid==""){

    echo "没有查询到站点";
}
else

{
    echo '站点id是
'. $siteid."\n";
echo '设置中...................
';

$res=$database->update("policies",
["server"=>$siteid],
["id="=>$id]
);

$da=$database->select("policies","*",["server="=>$siteid]);
if($da){
	echo "设置存储策略sharepoint成功\n";

}else{echo "设置失败";}



}
    }
}





array_shift($argv);
//$action = str_replace(':', '_', array_shift($argv));
$action=array_shift($argv);
if (is_callable(['sp', $action])) {
    @call_user_func_array(['sp', $action], $argv);

    exit();
}

     // $refresh_token=$row["access_key"];
    //  $client_id=$row["bucket_name"];
    //  $client_secret=$row["secret_key"];
      //$redirect_uri=json_decode($row["options"],true)["od_redirect"];//["od_redirect"];

    

// $cc=get_accesstoken($refresh_token,$client_id,$client_secret,$redirect_uri);

//echo get_siteidbyname("jane", $cc);
    



echo getcwd();











