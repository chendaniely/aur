library(rvest)
library(yaml)
library(stringr)
library(git2r)
library(fs)
library(digest)
library(glue)

source("helper.R")

url_rstudio_daily <- "https://dailies.rstudio.com/"
url_pkgbuild <- "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=rstudio-desktop-daily-bin"

pkgbuild_name_version <- get_pkgbuild_name_version(url_pkgbuild)

stopifnot(pkgbuild_name_version["pkgname"] == "rstudio-desktop-daily-bin")

## Get info from daily page
## This part will vary for different rstudio versions

page <- xml2::read_html(url_rstudio_daily)

xenial <- page %>%
  rvest::html_nodes("#ql-rstudio-oss-xenial-x86_64")

daily_url <- xenial %>%
  rvest::html_attr('href')

daily_version <- daily_url %>%
  stringr::str_extract("(?<=amd64/rstudio-).*(?=-amd64\\.deb)") %>%
  stringr::str_trim()

## Create list of values
update_info <- list(
  deb_url = daily_url,
  deb_name = fs::path_file(daily_url),
  deb_version = daily_version,

  # "https://aur.archlinux.org/rstudio-desktop-daily-bin.git"
  aur_url = "ssh://aur@aur.archlinux.org/rstudio-desktop-daily-bin.git",
  aur_version = pkgbuild_name_version$pkgversion,

  local_clone_pth = paste(tempdir(), 'rstudio-desktop-daily-bin', sep = '/'),

  git_credentials = git2r::cred_ssh_key(
    publickey = ssh_path("id_rsa.pub"),
    privatekey = ssh_path("id_rsa"),
    passphrase = character(0)
  )
)

if (update_info$deb_version == update_info$aur_version) {
  message("Versions match. Not updating.")
} else {
  #aur_git_pth <- paste(tempdir(), 'rstudio-desktop-daily-bin', sep = '/')
  #remote_url <- "ssh://aur@aur.archlinux.org/rstudio-desktop-daily-bin.git"
  #remote_url <- "https://aur.archlinux.org/rstudio-desktop-daily-bin.git"

  if (fs::dir_exists(update_info$local_clone_pth)) {fs::dir_delete(update_info$local_clone_pth)}

  git2r::clone(url = update_info$aur_url,
               local_path = update_info$local_clone_pth,
               credentials = update_info$git_credentials)

  local_info <- list(
    pkgbuild_pth = paste(update_info$local_clone_pth, "PKGBUILD", sep = "/"),
    deb_pth = paste(update_info$local_clone_pth, update_info$deb_name, sep = "/")
  )

  #clone_pkgbuild_pth <- paste(update_info$local_clone_pth, "PKGBUILD", sep = "/")
  clone_pkgbuild <- readLines(local_info$pkgbuild_pth)
  pkgver_line <- clone_pkgbuild[[11]]
  sha256sum_line <- clone_pkgbuild[[25]]

  stopifnot(stringr::str_starts(pkgver_line, "pkgver="))
  stopifnot(stringr::str_starts(sha256sum_line, "sha256sums_x86_64="))

  #xenial_deb_pth <- paste(update_info$local_clone_pth, update_info$deb_name, sep = "/")
  download.file(update_info$deb_url, destfile = local_info$deb_pth)

  #sha256 <- digest::digest(local_info$deb_pth, algo = "sha256")
  sha256 <- system2("sha256sum", local_info$deb_pth, stdout = TRUE) %>%
    stringr::str_split_fixed(" ", n = 2) %>%
    .[,1]

  new_pkgver_line <- stringr::str_replace(pkgver_line,
                                          pattern = "(?<=\\=).*",
                                          replacement = daily_version)
  new_sha256sum_line <- stringr::str_replace(sha256sum_line,
                                             pattern = "(?<=\\(').*(?='\\))", # between the round brackets
                                             replacement = sha256)

  clone_pkgbuild[[11]] <- new_pkgver_line
  clone_pkgbuild[[25]] <- new_sha256sum_line

  writeLines(text = clone_pkgbuild, con = local_info$pkgbuild_pth)

  cwd <- getwd()

  setwd(update_info$local_clone_pth)
  system2("mksrcinfo", local_info$pkgbuild_pth)
  fs::dir_ls(all = TRUE)

  print(git2r::status())

  git2r::add(repo = '.', path = c("PKGBUILD", ".SRCINFO"))
  git2r::commit(message = glue::glue("Semi-auto update: v{daily_version}-1"))

  git2r::status()

  git2r::push(credentials = update_info$git_credentials)

  print(git2r::status())

  setwd(cwd)
}
