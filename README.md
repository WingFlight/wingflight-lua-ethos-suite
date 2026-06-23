
![Wingflight](https://github.com/rotorflight/rotorflight/blob/master/images/rotorflight2.png?raw=true)

# WFSuite Lua Scripts for Ethos

**Wingflight** is a powerful flight control software suite built specifically for **fixed-wing RC aircraft**. It is not designed for multirotors or helicopters. The software includes:

-   **Wingflight Flight Controller Firmware**
    
-   **Wingflight Configurator** – used for flashing and configuring the flight controller
    
-   **Wingflight Blackbox Explorer** – for analyzing flight logs
    
-   **Wingflight Lua Scripts** – used to configure the flight controller directly from your transmitter
    

These scripts support the following transmitter operating systems:

-   **EdgeTX / OpenTX**
    
-   **Ethos** (this repository)
    

Wingflight is a fixed-wing fork of [Rotorflight](https://github.com/rotorflight), which is itself based on **Betaflight 4.3**.

> Note: the screenshots and web-simulator demo linked below still show the upstream Rotorflight UI/branding — they haven't been retaken for Wingflight yet. Treat them as illustrative of the underlying suite, not final Wingflight branding.

----------

## What is WFSuite?

**WFSuite** is a touch-based, Lua-scripted GUI suite for the Ethos platform. It enables easy setup, tuning, and diagnostics of Wingflight-based aircraft using supported FrSky transmitters. It offers:

-   Full touchscreen interface
    
-   FrSky and ELRS receiver compatibility
    
-   Multiple embedded tools and widgets
    

You can preview the experience using the interactive simulator:

👉 [**Launch Web Simulator**](https://ethos.studio1247.com/nightly16/X20PRO_FCC?backup=https://github.com/rotorflight/rotorflight-lua-ethos-suite/raw/refs/heads/master/demo/DEMO.zip&reset=all&language=en)

This opens the WFSuite in your browser, showcasing its functionality within the Ethos UI.

### Key UI Screens

**Status Widget**  
Dashboard themes are available for different flight states. See the [Dashboard Themes Overview](docs/dashboard-themes/) to compare the available theme previews.

![Status](https://raw.githubusercontent.com/rotorflight/rotorflight-lua-ethos-suite/master/.github/gfx/status.png)

**Flight Logs**  
![Flight Logs](https://raw.githubusercontent.com/rotorflight/rotorflight-lua-ethos-suite/master/.github/gfx/logs.png)

**FBL Configuration (Home)**  
![FBL Config](https://raw.githubusercontent.com/rotorflight/rotorflight-lua-ethos-suite/master/.github/gfx/home.png)

**Governor Configuration**  
![Governor Config](https://raw.githubusercontent.com/rotorflight/rotorflight-lua-ethos-suite/master/.github/gfx/gov.png)

----------

## Features

Inherited from Rotorflight/Betaflight, including:

### Protocol Support

-   Receiver: CRSF, S.BUS, F.Port, DSM, IBUS, XBUS, EXBUS, GHOST, CPPM
    
-   Telemetry: CRSF, S.Port, HoTT, and more
    
-   ESC telemetry: BLHeli32, Hobbywing, Scorpion, Kontronik, OMP Hobby, ZTW, APD, YGE
    

### Remote Tuning & Configuration

-   Via transmitter knobs/switches
    
-   Lua script interface on EdgeTX/OpenTX/Ethos
    

### Additional Capabilities

-   AUX outputs for custom motor/servo functions
    
-   Fully customizable mixer
    
-   Sensor support: voltage, current, BEC, etc.
    
-   Advanced filtering: Dynamic RPM notch, FFT-based notch, and LPF
    
-   High-speed Blackbox logging
    

### Plus Betaflight-Inherited Features:

-   Multiple configuration and rate profiles
    
-   DSHOT, PWM, Multishot ESC protocols
    
-   RGB LEDs and buzzers
    
-   GPS integration
    

> Note: the helicopter-specific feature list (rotor governor, swash/TTA tuning, etc.) from the
> Rotorflight original has been dropped above pending a proper fixed-wing feature audit — this
> still needs a follow-up pass.

----------

## Lua Script Requirements

To use WFSuite, you'll need:

-   **Ethos 1.6.2 or later**
    
-   A compatible FrSky transmitter:
    
    -   X10, X12, X14, X18, X20, or Twin X Lite
        
-   A supported receiver:
    
    -   FrSky (Smartport or F.Port over ACCESS, ACCST, TD, TW)
        
    -   ExpressLRS (ELRS) modules supported by Ethos
        

----------

## Verified Compatible Receivers

WFSuite has been successfully tested on the following receiver models (with X10, X14, X18, X20, XLite):

-   TWMX
    
-   TD MX
    
-   R9 MX ACCESS
    
-   R9 Mini ACCESS
    
-   Archer RS / Archer Plus RS / RS Mini (ACCESS / F.Port)
    
-   RX6R ACCESS
    
-   R-XSR ACCESS / ACCST F.Port
    
-   ELRS (all versions)

----------    

## Installation Instructions

### Radio Updater (GUI)

For Windows, Mac & Linux users, a prebuilt GUI updater is available to simplify updating files on the radio without using VS Code or Python. Wingflight doesn't have its own updater build yet, so the Rotorflight updater tool is referenced here in the meantime:

- **Download:** https://github.com/rotorflight/rotorflight-lua-ethos-suite-updater/releases
- Standalone Windows executable (plus macOS/Linux builds)
- Intended for end users or quick updates

![Updater](https://raw.githubusercontent.com/rotorflight/rotorflight-lua-ethos-suite-updater/master/.github/gfx/updater.png)


----------

## Development Guide

To build and deploy WFSuite locally:

### Requirements

See `docs/dev-environment.md` for the full developer environment setup guide.

-   Visual Studio Code (VS Code)
    
-   Python 3
    
-   Install libraries
    
    ```bash
    python -m pip install -r requirements.txt
    ```

-   On Windows, install this package if radio HID control cannot find `hidapi.dll`:

     https://github.com/libusb/hidapi/releases/tag/hidapi-0.15.0

     Simply copy the dll's for your architecture into c:\windows\system32

-   On macOS, install the native HID library before installing Python packages:

    ```bash
    brew install hidapi
    ```

- Install the VS Code extension `Ethos`


### VS Code Tasks

-   **Deploy & Launch** – Pushes scripts to the default simulator

-   **Deploy & Choose** – Pushes scripts to the selected simulator 
    
-   **Deploy Radio** – Pushes scripts to the radio

-   **Deploy Radio and  Debug** – Pushes scripts to the radio and starts serial console
    

----------

## Installation Instructions

1.  Download the latest files:
    
    -   Click **Code** > **Download ZIP**
        
2.  Install using the Ethos Suite Lua Tools on your transmitter.
    

----------

## Contributing

Wingflight is a community-driven open-source project. You can contribute by:

-   Helping other users in [GitHub Discussions](https://github.com/WingFlight) or forums
    
-   Reporting issues or requesting features via [GitHub](https://github.com/WingFlight)
    
-   Testing and giving feedback on new versions
    
-   Updating documentation and tutorials
    
-   Translating the suite into other languages
    
-   Contributing code (fixes, features, enhancements)
    

----------

## Project Origins

Wingflight is **open source** and available free of charge, with no warranties.

-   Forked from [Rotorflight](https://github.com/rotorflight)
-   Which was forked from [Betaflight](https://github.com/betaflight)
    
-   Which was forked from [Cleanflight](https://github.com/cleanflight)
    

🙏 A big thank you to everyone who has contributed along the way!

----------

## Contact

📧 Reach out to the Wingflight team via [GitHub Issues and Discussions](https://github.com/WingFlight).
