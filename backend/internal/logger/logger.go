package logger

import (
	"io"
	"os"

	"github.com/kataras/golog"
)

var Log *golog.Logger

func init() {
	Log = golog.New()
	Log.SetLevel("debug")

	env := os.Getenv("APPENV")
	if env == "production" {
		//JSON format for production
		Log.SetFormat("JSON")
		Log.SetOutput(os.Stdout)
	} else {
		//Dev mode: Colour console + local file
		Log.SetFormat("TEXT")
		Log.SetTimeFormat("2006-01-02 15:04:05")

		f, err := os.OpenFile("app.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			Log.Fatalf("Failed to open log file: %v", err)
		}
		//Multiwriter outputs to both stdout and file
		mw := io.MultiWriter(os.Stdout, f)
		Log.SetOutput(mw)
		// Intentionally keep file open for the duration of the process to ensure logging continues
	}
	Log.Infof("Logger initialised in %s mode", env)
}
