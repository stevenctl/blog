format:
	find ./content -type f -name "*.md" | xargs markdownlint-cli2 --fix 

serve:
	hugo server --disableFastRender

