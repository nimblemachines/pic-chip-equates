# Makefile to generate muforth equates files from Microchip .ini files, which
# in turn come from downloaded .atpack files.

### Variables

CHIPS=		16f1454 \
		18f13k50 18f14k50 \
		18f14q41 18f15q41 18f16q41 \
		18f55q43 18f56q43 18f57q43 \
		18f54q71 18f55q71 18f56q71 \
		18f56q84 18f57q84

MU4_FILES=	$(patsubst %,mu/%.mu4,$(CHIPS))

vpath %.ini $(wildcard ini/*/)


### Main targets

.PHONY : chips example get-example-packs

# Default target
# Since unzip-packs might have created new ini/<something> directories, chips
# cannot be a pre-requisite target; it needs to be a recursive invocation of
# make in order to re-eval vpath.
example : get-example-packs unzip-packs
	make chips

# Show the packs needed for the example CHIPS variable defined above. This can
# be useful to check version numbers.
show-example-packs :
	MATCH="PIC12%-16F1" make show-packs
	MATCH="PIC18F%-J" make show-packs
	MATCH="PIC18F%-K" make show-packs
	MATCH="PIC18F%-Q" make show-packs

# Download the packs needed for the example CHIPS variable defined above.
get-example-packs :
	MATCH="PIC12%-16F1" make get-packs
	MATCH="PIC18F%-J" make get-packs
	MATCH="PIC18F%-K" make get-packs
	MATCH="PIC18F%-Q" make get-packs

chips : $(MU4_FILES)


### Generating .mu4 files from .ini files

mu :
	mkdir mu/

$(MU4_FILES) : ini2mu4.lua mu

mu/%.mu4 : %.ini
	lua ini2mu4.lua $< > $@


### Downloading and parsing Microchip's pack repository index file.

.PHONY : update

PACK_URL=	https://packs.download.microchip.com/

mchp-pack-index.html update :
	curl -o mchp-pack-index.html $(PACK_URL)

mchp-pack-index.lua : mchp-pack-index.html parse-pack-index.lua
	lua parse-pack-index.lua < $< > $@


### Downloading pack files

.PHONY : show-packs get-packs

pack :
	mkdir pack

show-packs : mchp-pack-index.lua
	@lua gen-downloads.lua $< $(PACK_URL) $(MATCH) show

get-packs : mchp-pack-index.lua pack
	@lua gen-downloads.lua $< $(PACK_URL) $(MATCH) get | sh


### Unzipping downloaded packs. We are interested mostly in the .ini files in
### xc8/pic/dat/ini.

.PHONY : unzip-packs

# NOTE: unzip -j will throw away paths, rather than recreating hierarchy
#
unzip-packs :
	for p in pack/*.atpack; do \
		dir=ini/$$(basename $$p .atpack); mkdir -p $$dir; \
		unzip -j -u $$p "*.ini" "*.cfgdata" -d $$dir; done


### Installing into a local muforth checkout

.PHONY : muforth-install

# Path to "install" .mu4 files. This should be a "muforth" directory.
MU_INSTALL_DIR=	$(HOME)/muforth

muforth-install : $(MU4_FILES)
	mkdir -p $(MU_INSTALL_DIR)/mu/target/PIC16/device
	cp -f mu/16f* $(MU_INSTALL_DIR)/mu/target/PIC16/device
	mkdir -p $(MU_INSTALL_DIR)/mu/target/PIC18/device
	cp -f mu/18f* $(MU_INSTALL_DIR)/mu/target/PIC18/device


### Cleaning up the mess

.PHONY : clean clean-ini clean-packs clean-index spotless

clean :
	rm -rf mu/

clean-ini :
	rm -rf ini/

clean-packs :
	rm -rf pack/

clean-index :
	rm -f mchp-pack-index.*

spotless : clean clean-index clean-packs clean-ini
