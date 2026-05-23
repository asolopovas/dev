package web

import "os"

const (
	publicDirMode   = 0755
	publicFileMode  = 0644
	privateDirMode  = 0750
	privateFileMode = 0600
)

func writePublicFile(path string, data []byte) error {
	return writeFileAtomic(path, data, publicFileMode)
}

func writePrivateFile(path string, data []byte) error {
	return writeFileAtomic(path, data, privateFileMode)
}

func ensurePublicDir(path string) error {
	return os.MkdirAll(path, publicDirMode)
}

func ensurePrivateDir(path string) error {
	return os.MkdirAll(path, privateDirMode)
}
