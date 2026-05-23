package web

type composeCommandSpec struct {
	Use   string
	Short string
	Args  []string
}

func shellCommandSpecs(cfg Config) []composeCommandSpec {
	values := cfg.ResolvedValues()
	return []composeCommandSpec{
		{Use: "bash", Short: "Container Bash", Args: []string{"exec", values.Services.FrankenPHP, "bash"}},
		{Use: "fish", Short: "Container Fish", Args: []string{"exec", values.Services.FrankenPHP, "fish"}},
	}
}

func databaseCommandSpecs(cfg Config) []composeCommandSpec {
	return []composeCommandSpec{
		{Use: "mysql", Short: "MySQL client as root", Args: mysqlRootShellArgs(cfg)},
	}
}

func redisCommandSpecs(cfg Config) []composeCommandSpec {
	redis := cfg.ResolvedValues().Services.Redis
	return []composeCommandSpec{
		{Use: "redis-cli", Short: "Redis CLI shell", Args: []string{"exec", redis, "redis-cli"}},
		{Use: "redis-flush", Short: "Flush Redis", Args: []string{"exec", redis, "redis-cli", "flushall"}},
		{Use: "redis-monitor", Short: "Monitor Redis", Args: []string{"exec", redis, "redis-cli", "monitor"}},
	}
}
