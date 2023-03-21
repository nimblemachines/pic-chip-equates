# Makefile to generate muforth equates files from Microchip .ini files, which
# in turn come from downloaded .atpack files.

### Variables

CHIPS=		16f1454 18f26q43 18f26q83
MU4_FILES=	$(patsubst %,%.mu4,$(CHIPS))
INI_DIRS=	$(wildcard ini/*/)

vpath %.ini $(INI_DIRS)


### Targets

all : $(MU4_FILES)


### Rules

$(MU4_FILES) : ini2mu4.lua

%.mu4 : %.ini
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
		unzip -j -u $$p "*.ini" -d $$dir; done


### Cleaning up the mess

.PHONY : clean clean-ini clean-packs clean-index spotless

clean :
	rm -f *.mu4

clean-ini :
	rm -rf ini/

clean-packs :
	rm -rf pack/

clean-index :
	rm -f mchp-pack-index.*

spotless : clean clean-index clean-packs clean-ini
