function kpatch () {
	git send-email \
		--cc-cmd="~/.cc.sh" \
		$@
}

function checkpatch() {
	~/working/src/linux/scripts/checkpatch.pl $@
}
