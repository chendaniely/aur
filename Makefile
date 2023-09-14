@phony: all
all:
	Rscript update_rstudio-desktop-daily-bin.R FALSE TRUE # no sleep; yes git
