#!/usr/bin/env roc
# Run:
#
#   ./watch.roc
#
# Serves the app at http://localhost:8000. Edit app.roc (or anything else)
# and it rebuilds automatically. Refresh the page to see your changes (there
# is no browser hot-reloading yet).
#
# Uses `roc build --watch` which writes no wasm at all in most error cases
# (e.g. type errors). If you refresh your browser and your app isn't showing up,
# then check your terminal for errors (you'll also see a crash in the browser
# console).
#
# Set the environment variable `JOY_WATCH_PORT` to change the port (default 8000).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.IOErr
import pf.Sleep
import pf.Stderr
import pf.Stdout

main! = |_args| {
	port = Env.var_str!("JOY_WATCH_PORT") ?? "9090"

	spawned =
		Cmd.new_str("python3")
			.args_str(["serve.py", port])
			.env_str("JOY_WATCH_PORT", port)
			.spawn!()

	python_server = match spawned {
		Ok(child) => child
		Err(SpawnFailed(err)) => log_and_exit!("caddy", err)?
	}

	# spawn! only reports that the process started, so give caddy a moment to parse its
	# config, then poll! to verify it's running
	Sleep.millis!(200)

	match python_server.poll!() {
		Ok(Running) => {}
		Ok(Exited(exited)) => {
			Stderr.line!("Error: caddy exited immediately (code ${exited.exit_code.to_str()}). Is ./Caddyfile OK?")?
			Stderr.line!(Str.from_utf8_lossy(exited.stderr))?
			Err(Exit(1))?
		}
		Err(PollFailed(_)) => Err(Exit(2))?
	}

	Stdout.line!("=> Serving the app at http://localhost:${port}")?

	# ./build.roc once up front so that Joy's runtime.js is copied out of the platform
	build = Cmd.new_str("./build.roc").env_str("PATH", "/tmp/roc:/usr/bin").exec_exit_code!()

	build_code = match build {
		Ok(code) => code
		Err(FailedToGetExitCode(failure)) => log_and_exit!("./build.roc", failure.err)?
	}

	if build_code != 0 {
		Stderr.line!("Warning: The first build failed, watching for changes anyway")?
	} else {
		{}
	}

	watch =
		Cmd.new_str("/tmp/roc/roc")
			.args_str(["build", "--watch", "--target=wasm32", "--output=www/app.wasm", "app.roc"])
			.exec_exit_code!()

	# `roc build --watch` above blocks, so we're killing caddy only when roc is dead
	python_server.kill!() ?? {}

	match watch {
		Ok(0) => Ok({})
		Ok(code) => Err(Exit(code))
		Err(FailedToGetExitCode(failure)) => log_and_exit!("roc", failure.err)?
	}
}

log_and_exit! = |program, err| {
	reason = match err {
		NotFound => "Not found (is it installed and available on PATH?)"
		other => IOErr.to_str(other)
	}

	Stderr.line!("Error: Could not run `${program}`: ${reason}")?
	Err(Exit(1))
}
