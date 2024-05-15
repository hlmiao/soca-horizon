
ifeq (${QUIET_MODE},true)
    pip_flags := --quiet
endif

resources/src/.requirements_installed: resources/src/requirements.txt
	@echo "Installing/upgrading required dependencies (this can take a couple of minutes)"
	pip3 install -i https://opentuna.cn/pypi/web/simple --upgrade pip ${pip_flags}
	pip3 install -i https://opentuna.cn/pypi/web/simple -r resources/src/requirements.txt ${pip_flags}
	touch $@
