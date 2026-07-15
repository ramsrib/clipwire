//go:build darwin

package main

import (
	"encoding/base64"
	"errors"
	"os/exec"
	"strings"
)

var errNoImage = errors.New("no image on clipboard")

// AppleScript-ObjC: read the clipboard image as PNG via NSPasteboard.
// Prefers public.png; falls back to converting public.tiff. Emits base64 of
// the PNG on stdout, or the literal "NONE" when the clipboard holds no image.
const clipboardScript = `use framework "AppKit"
use framework "Foundation"
set pb to current application's NSPasteboard's generalPasteboard()
set pngData to pb's dataForType:"public.png"
if pngData is missing value then
set tiffData to pb's dataForType:"public.tiff"
if tiffData is missing value then
return "NONE"
end if
set theRep to current application's NSBitmapImageRep's imageRepWithData:tiffData
set pngData to theRep's representationUsingType:(current application's NSBitmapImageFileTypePNG) |properties|:(current application's NSDictionary's dictionary())
end if
return (pngData's base64EncodedStringWithOptions:0) as text`

func readClipboardPNG() ([]byte, error) {
	cmd := exec.Command("osascript")
	cmd.Stdin = strings.NewReader(clipboardScript)
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	s := strings.TrimSpace(string(out))
	if s == "" || s == "NONE" {
		return nil, errNoImage
	}
	data, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, err
	}
	return data, nil
}
