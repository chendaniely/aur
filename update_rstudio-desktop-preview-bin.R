library(jsonlite)
library(glue)
library(git2r)

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

  aur_git_pth <- paste(tempdir(), 'rstudio-desktop-preview-bin', sep = '/')
  remote_url <- "ssh://aur@aur.archlinux.org/rstudio-desktop-preview-bin.git"

  git_credentials <- git2r::cred_ssh_key(
    publickey = ssh_path("id_rsa.pub"),
    privatekey = ssh_path("id_rsa"),
    passphrase = character(0)
  )

  clone_from_aur(remote_url, aur_git_pth, git_credentials)

  update_pkgbuild_file(aur_git_pth, rstudio_desktop_preview_bionic$s3_url, rstudio_desktop_preview_bionic$version)

  mksrcinfo(aur_git_pth)

  git_add_commit_push(aur_git_pth,
                      message = glue::glue("Semi-auto update: v{rstudio_desktop_preview_bionic$version}"),
                      git_credentials,
                      push = TRUE)
}
