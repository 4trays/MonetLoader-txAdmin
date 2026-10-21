# MonetLoader-txAdmin
# Requirements & Dependencies

> External libraries required by the **MonetLoader TXAdmin WebView**
> script.

## Runtime requirement

-   **MonetLoader:** `v3.8.0`
-   **Client:** A compatible SA-MP Android client
-   **WebView module:** A build compatible with MonetLoader `v3.8.0` and
    the target Android client

This repository does **not** bundle third-party libraries. Install the
required dependencies in a compatible environment before running the
script.

## Required dependencies

The script imports the following modules:

``` lua
require('lib.moonloader')
require('encoding').default = 'CP1251'

local u8 = require('encoding').UTF8
local ev = require('samp.events')
local inicfg = require('inicfg')
local lib = require('webviews')
```

  -----------------------------------------------------------------------
  Module                  Purpose                 Notes
  ----------------------- ----------------------- -----------------------
  `lib.moonloader`        Runtime functions       Provided by the
                          exposed by the loader   compatible loader
                          environment             environment; it is not
                                                  a standalone Lua
                                                  package.

  `encoding`              Text encoding           Must support the
                          conversion              `CP1251` default and
                                                  UTF-8 conversion used
                                                  by the script.

  `samp.events`           SA-MP event callbacks   Use a version
                          and event handling      compatible with the
                                                  target client and
                                                  MonetLoader `v3.8.0`.

  `inicfg`                Read and write          Must be available to
                          INI-style configuration the Lua runtime.

  `webviews`              WebView integration for Requires a compatible
                          the script's interface  module/build for
                                                  MonetLoader `v3.8.0`
                                                  and the target Android
                                                  client.
  -----------------------------------------------------------------------

## Installation checklist

1.  **Install/verify MonetLoader `v3.8.0`.** The script is intended for
    this version; other versions are not guaranteed to work.
2.  **Check the SA-MP Android client.** Use a client compatible with the
    installed MonetLoader build.
3.  **Install missing dependencies** from their maintainers' official
    repositories or trusted distribution sources.
4.  **Keep module names unchanged.** Names passed to `require(...)` must
    match the modules installed in your Lua environment.
5.  **Restart the game/client** after installing or updating libraries,
    then inspect the MonetLoader log if the script fails to load.

## Troubleshooting

-   `module '...' not found`: the module may be missing, installed in
    the wrong directory, or named differently from the `require(...)`
    call.
-   `attempt to index a nil value`: the module may have loaded
    differently than expected, or the installed version may not expose
    the API the script uses.
-   WebView-related errors: verify that the `webviews` module supports
    MonetLoader `v3.8.0` and your Android client.
-   Encoding/display issues: verify `CP1251` and UTF-8 support and check
    how strings are converted before display.
-   Crashes or inconsistent behavior: record the exact MonetLoader
    build, client version, dependency versions, and relevant log lines.

## Third-party library policy

Third-party libraries are intentionally excluded from this repository to
keep the project lightweight and respect their maintainers' distribution
terms.

-   Download dependencies only from sources you trust.
-   Review each dependency's own license and usage conditions.
-   Do not assume this repository's license also applies to third-party
    libraries.
-   This project does not claim ownership of the dependencies listed
    above.

## Compatibility

The target runtime is **MonetLoader `v3.8.0`**. Compatibility may still
depend on the SA-MP Android client and the specific versions/builds of
the `samp.events`, `inicfg`, and `webviews` modules installed. Do not
assume every combination is supported without testing.

When reporting an issue, include:

-   SA-MP Android client and version
-   MonetLoader version (`v3.8.0`)
-   Name/version/source of the dependency that fails
-   Relevant error lines from the MonetLoader log

------------------------------------------------------------------------

**Recommended filename:** `REQUIREMENTS.md`\
Keep it in the repository root and link to it from `README.md`.

