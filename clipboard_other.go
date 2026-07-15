//go:build !darwin

package main

import "errors"

var errNoImage = errors.New("no image on clipboard")

func readClipboardPNG() ([]byte, error) {
	return nil, errors.New("clipwire serve is only supported on macOS")
}
