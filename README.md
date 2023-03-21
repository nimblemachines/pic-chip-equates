# What is this project and why does it exist?

## Motivation

I'm interested in supporting Microchip's PIC16, PIC18 &ndash; and, possibly, PIC24 and dsPIC33 &ndash; chips in [muforth](https://muforth.nimblemachines.com/).

One of the issues with rolling your own language &ndash; especially if, like [muforth](https://muforth.nimblemachines.com/), it is a cross-compiler that targets microcontrollers &ndash; is that you need to find or create, for every chip you care about, "equates" files that describe the i/o registers, their memory addresses, and their bit definitions.

## Approaches we could take

It's a lot of work &ndash; and error-prone &ndash; to type these in by hand. For the Freescale S08 and the Atmel AVR I was able to get pretty good results by "scraping" the PDF files by hand (yes, by hand, with a mouse), pasting the results into a file, and then running code that processed the text into a useful form.

For the [STM32 ARM microcontrollers](https://github.com/nimblemachines/stm32-chip-equates) I wrote code that shoddily "parses" .h files (which I found in ST's "Std Periph Lib" and STM32Cube zip files &ndash; I tried both) and prints out muforth code.

I did something similar for [Freescale's Kinetis microcontrollers](https://github.com/nimblemachines/kinetis-chip-equates), only instead of trying to parse .h files, I discovered Keil's CMSIS-SVD files, and Keil's CMSIS-Pack database, and wrote code to download pack files, and parse the constituent SVD files.

## The mother lode

Microchip has done something similar: they have a [pack repository site](https://packs.download.microchip.com/), where they host ``.atpack`` files, which are ZIP archives of chip support files needed for their toolchains. In particular, in each family pack, there is a directory of ``.ini`` files that describe the memory layout, i/o register addresses, and the bit fields making up each i/o register.

This is our goldmine.

# How do I use it?

First you need to figure out which packs you need to download. To see a list of everything, do:

    MATCH="." make show-packs

The MATCH variable is a Lua pattern, not a POSIX regular expression, but it shouldn't be hard to narrow down the list by changing the MATCH expression. ``.`` matches any character; ``+`` as a suffix does a greedy "zero or more" match of the preceding character; ``-`` does a non-greedy "zero or more" match.

Once you have a list that you like, change ``show-packs`` to ``get-packs``. The packs will be downloaded and placed in the ``pack/`` directory.

    make unzip-packs

will unzip any ``.ini`` files found in the packs into a subdirectory of the ``ini/`` directory, with the same name as the pack. Find the chips that you are interested in in one these subdirectories, and put their names &ndash; minus the ``.ini`` extension &ndash; in the Makefile as the value of the ``CHIPS`` variable.

If you later download more pack files, ``make unzip-packs`` will only unzip the new files. It will leave any existing files alone.

Also, if you want to make sure you have the latest list, ``make update`` will force a download of the pack index.

Once you have populated ``ini/`` and set the ``CHIPS`` variable, do

    make

and a ``.mu4`` file will be generated for each chip that you specified.

# BSD-licensed!

See the `LICENSE` file for details. Do whatever you want! Have fun!
