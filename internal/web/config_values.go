package web

func (c Config) ResolvedValues() AppValues {
	if c.Values.Files.Compose == "" {
		return DefaultAppValues()
	}
	return c.Values
}
