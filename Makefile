@phony: all
all:
	Rscript update_rstudio-desktop-daily-bin.R FALSE TRUE # no sleep; yes git

@phony: install
install:
	Rscript -e "install.packages(c('rvest', 'yaml', 'git2r', 'fs', 'digest'), repo = 'http://cran.rstudio.com')"

