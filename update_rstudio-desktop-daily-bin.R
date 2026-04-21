#
# Rscript update_rstudio-desktop-daily-bin.R FALSE TRUE # no sleep; yes git
#
#

library(rvest)
library(yaml)
library(stringr)
library(git2r)
library(fs)
library(digest)
library(glue)
library(credentials)

options(timeout=180)

args <- commandArgs(trailingOnly = TRUE)
print(args)

if (length(args) == 0 | interactive()) {
  message("No args passed. No Git.")
  git_bool = FALSE

} else {
  stopifnot(length(args) == 2)
  git_bool = as.logical(args[[2]])
}

source("helper.R")

print(date())


url_rstudio_daily <- "https://dailies.rstudio.com/"
url_pkgbuild <- "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=rstudio-desktop-daily-bin"

pkgbuild_name_version <- get_pkgbuild_name_version(url_pkgbuild)

stopifnot(pkgbuild_name_version["pkgname"] == "rstudio-desktop-daily-bin")

## Get info from daily page
## This part will vary for different rstudio versions

page <- xml2::read_html(url_rstudio_daily)

ubuntu <- page %>%
  rvest::html_node(xpath = "/html/body/main/div/div[2]/div[3]/a")

daily_url <- ubuntu %>%
  rvest::html_attr('href')

daily_version <- daily_url %>%
  stringr::str_extract("(?<=amd64/rstudio-).*(?=-amd64\\.deb)") %>%
  stringr::str_trim()

## Create list of values
update_info <- list(
  deb_url = daily_url,
  deb_name = fs::path_file(daily_url),
  deb_version = daily_version,

  aur_url = "ssh://aur@aur.archlinux.org/rstudio-desktop-daily-bin.git",
  aur_version = pkgbuild_name_version$pkgversion,
  aur_ver_url = pkgbuild_name_version$pkgver_url,

  local_clone_pth = paste(tempdir(), 'rstudio-desktop-daily-bin', sep = '/')
)

if (update_info$deb_version == update_info$aur_ver_url) {
  message("Versions match. Not updating.")
} else {
  if (fs::dir_exists(update_info$local_clone_pth)) {
    fs::dir_delete(update_info$local_clone_pth)
    fs::dir_create(update_info$local_clone_pth)
  }

  system(glue::glue("git clone {update_info$aur_url} {update_info$local_clone_pth}"))

  local_info <- list(
    pkgbuild_pth = paste(update_info$local_clone_pth, "PKGBUILD", sep = "/"),
    srcinfo_pth = paste(update_info$local_clone_pth, ".SRCINFO", sep = "/"),
    deb_pth = paste(update_info$local_clone_pth, update_info$deb_name, sep = "/")
  )

  clone_pkgbuild <- readLines(local_info$pkgbuild_pth)

  pkgver_idx      <- which(stringr::str_starts(clone_pkgbuild, "pkgver="))
  pkgver_url_idx  <- which(stringr::str_starts(clone_pkgbuild, "pkgver_url="))
  sha256sum_idx   <- which(stringr::str_starts(clone_pkgbuild, "sha256sums_x86_64="))

  stopifnot(length(pkgver_idx) == 1, length(pkgver_url_idx) == 1, length(sha256sum_idx) == 1)

  pkgver_line     <- clone_pkgbuild[[pkgver_idx]]
  pkgver_url_line <- clone_pkgbuild[[pkgver_url_idx]]
  sha256sum_line  <- clone_pkgbuild[[sha256sum_idx]]

  download.file(update_info$deb_url, destfile = local_info$deb_pth)

  sha256 <- digest::digest(local_info$deb_pth, algo = "sha256", file = TRUE)

  new_pkgver_line <- stringr::str_replace(pkgver_line,
                                          pattern = "(?<=\\=).*",
                                          replacement = stringr::str_replace_all(daily_version, "-", ".")) %>%
    stringr::str_replace_all("%2B", "+")

  new_pkgver_url_line <- stringr::str_replace(pkgver_url_line,
                                              pattern = "(?<=\\=).*", # everything after the "="
                                              replacement = daily_version)

  new_sha256sum_line <- stringr::str_replace(sha256sum_line,
                                             pattern = "(?<=\\(').*(?='\\))", # between the round brackets
                                             replacement = sha256)

  clone_pkgbuild[[pkgver_idx]]     <- new_pkgver_line
  clone_pkgbuild[[pkgver_url_idx]] <- new_pkgver_url_line
  clone_pkgbuild[[sha256sum_idx]]  <- new_sha256sum_line

  writeLines(text = clone_pkgbuild, con = local_info$pkgbuild_pth)

  cwd <- getwd()

  setwd(update_info$local_clone_pth)
  system2("makepkg", args = "--printsrcinfo", stdout = local_info$srcinfo_pth)

  if (git_bool) {
    print(git2r::status())

    git2r::add(repo = '.', path = c("PKGBUILD", ".SRCINFO"))
    git2r::commit(message = glue::glue("Semi-auto update: v{stringr::str_replace_all(daily_version, '%2B', '+')}-1"))

    system(glue::glue("git push origin master"))

    print(git2r::status())
  }

  setwd(cwd)

  fs::dir_delete(update_info$local_clone_pth)
}
