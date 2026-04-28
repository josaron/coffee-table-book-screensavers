THEME      ?= sample
ROKU_IP    ?= 192.168.4.23
ROKU_PASS  ?= Roku1234
MAX_WIDTH  ?= 1920

.PHONY: build deploy clean list-themes

build:
	./build.sh $(THEME) $(MAX_WIDTH)

# Sideload to a Roku device in developer mode.
# Enable developer mode: Settings > System > Advanced system settings > Developer mode
# Then: make deploy THEME=sample ROKU_IP=192.168.1.x ROKU_PASS=yourpassword
deploy: build
	@if [ -z "$(ROKU_IP)" ]; then \
	  echo "ERROR: set ROKU_IP=<device-ip>  (and optionally ROKU_PASS=<password>)"; \
	  exit 1; \
	fi
	curl -s -S --user rokudev:$(ROKU_PASS) --anyauth \
	  -F "mysubmit=Install" \
	  -F "archive=@dist/$(THEME).zip" \
	  "http://$(ROKU_IP)/plugin_install" | grep -oE '<font color="red">[^<]+' | sed 's/<font color="red">//'
	@echo "Deployed $(THEME) → Roku @ $(ROKU_IP)"

clean:
	rm -rf build/ dist/

list-themes:
	@ls themes/
