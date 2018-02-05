#  [Echem-Pi](https://github.com/toshinagata/echempi): How to set up the Raspberry Pi

##  Raspberry Pi Model

The Raspberry Pi Model A+ is a suitable choice. The Pi2 and Pi3 are also good but expensive. The Model Zero should be good, but at the time of this writing it is not so widely available.

##  LCD Touch Screen

Echem-Pi is designed to work with a secondary LCD screen (HDMI screen is not used) with a touch screen. The author uses a [Waveshare 3.2-inch LCD](https://www.waveshare.com/wiki/3.2inch_RPi_LCD_(B)).

##  How to set up

###  OS

The 'lite' version of the Raspbian is sufficient. Use Raspbian Jessie Lite or Stretch Lite. After installing the OS, the BOOT option is set to 'Console Autologin' by `raspi-config`.

###  Additional Packages

The following packages are necessary: `wiringpi`, `tslib`, `evtest`, `libts-bin`.
Install them by the following command line.

    $ sudo apt-get install wiringpi tslib evtest libts-bin

###  Set up LCD and Touch Screen

See [swkim01/waveshare-dtoverlays](https://github.com/swkim01/waveshare-dtoverlays).

###  Install Software

Copy the `echem` directory to the home directory.

Copy `bash_profile` to the home directory and rename it to `.bash_profile` (note the period).
Or, if you already use `.bash_profile` for any other purpose, copy the content of `bash_profile` and append it to your `.bash_profile`.
