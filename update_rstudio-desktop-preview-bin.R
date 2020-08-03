library(jsonlite)
library(glue)

source("helper.R")

pkgbuild_url <- "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=rstudio-desktop-preview-bin"
pkgbuild_name_version <- get_pkgbuild_name_version(pkgbuild_url)
pkgbuild_name_version

stopifnot(pkgbuild_name_version["pkgname"] == "rstudio-desktop-preview-bin")

## get info from rstudio json

rstudio_download_json_url <- "https://rstudio.com/wp-content/downloads.json"

rstudio_download_json <- jsonlite::read_json(rstudio_download_json_url)

rstudio_desktop_preview_bionic <- rstudio_download_json$rstudio$open_source$preview$desktop$installer$bionic


if (rstudio_desktop_preview_bionic$version == pkgbuild_name_version$pkgversion) {
  message("Nothing to do. Versions match.")
} else {
  message(glue::glue(
    "AUR version:     {pkgbuild_name_version$pkgversion}
     RStudio version: {rstudio_desktop_preview_bionic$version}"
  ))
}
