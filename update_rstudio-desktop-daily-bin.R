library(rvest)
library(yaml)
library(stringr)
library(git2r)
library(fs)
library(digest)
library(glue)

url_rstudio_daily <- "https://dailies.rstudio.com/"
url_pkgbuild <- "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=rstudio-desktop-daily-bin"


## Read pkgbuild file from AUR
pth_pkgfile <- tempfile()

download.file(url_pkgbuild, destfile = pth_pkgfile)

pkgbuild <- readLines(pth_pkgfile)

pkgversion <- pkgbuild[stringr::str_detect(pkgbuild, "pkgname=|pkgver=")]

stopifnot(length(pkgversion) == 2)

pkgname <-  pkgversion[[1]] %>%
  stringr::str_split_fixed(pattern = "=", n = 2) %>%
  .[,2]

pkgversion <- pkgversion[[2]] %>%
  stringr::str_split_fixed(pattern = "=", n = 2) %>%
  .[,2] %>%
  stringr::str_trim()

stopifnot(pkgname == "rstudio-desktop-daily-bin")

## Get info from daily page

page <- xml2::read_html(url_rstudio_daily)

xenial <- page %>%
  rvest::html_nodes("#ql-rstudio-oss-xenial-x86_64")

daily_url <- xenial %>%
  rvest::html_attr('href')

daily_version <- daily_url %>%
  stringr::str_extract("(?<=amd64/rstudio-).*(?=-amd64\\.deb)") %>%
  stringr::str_trim()

if (pkgversion == daily_version) {
  message("Versions match. Not updating.")
} else {
  aur_git_pth <- paste(tempdir(), 'rstudio-desktop-daily-bin', sep = '/')
  remote_url <- "ssh://aur@aur.archlinux.org/rstudio-desktop-daily-bin.git"
  #remote_url <- "https://aur.archlinux.org/rstudio-desktop-daily-bin.git"

  if (fs::dir_exists(aur_git_pth)) {fs::dir_delete(aur_git_pth)}

  git_credentials <- git2r::cred_ssh_key(
    publickey = ssh_path("id_rsa.pub"),
    privatekey = ssh_path("id_rsa"),
    passphrase = character(0)
  )


  git2r::clone(url = remote_url,
               local_path = aur_git_pth,
               credentials = git_credentials)


  clone_pkgbuild_pth <- paste(aur_git_pth, "PKGBUILD", sep = "/")

  clone_pkgbuild <- readLines(clone_pkgbuild_pth)

  pkgver_line <- clone_pkgbuild[[11]]
  sha256sum_line <- clone_pkgbuild[[25]]

  stopifnot(stringr::str_starts(pkgver_line, "pkgver="))
  stopifnot(stringr::str_starts(sha256sum_line, "sha256sums_x86_64="))

  xenial_deb_pth <- paste(aur_git_pth, fs::path_file(daily_url), sep = "/")

  download.file(daily_url, destfile = xenial_deb_pth)

  #sha256 <- digest::digest(xenial_deb_pth, algo = "sha256")
  sha256 <- system2("sha256sum", xenial_deb_pth, stdout = TRUE) %>%
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

  writeLines(text = clone_pkgbuild, con = clone_pkgbuild_pth)

  cwd <- getwd()

  setwd(aur_git_pth)
  system2("mksrcinfo", clone_pkgbuild_pth)
  fs::dir_ls(all = TRUE)

  git2r::status()

  git2r::add(repo = '.', path = c("PKGBUILD", ".SRCINFO"))
  git2r::commit(message = glue::glue("Auto update: v{daily_version}-2"))

  git2r::status()

  git2r::push(credentials = git_credentials)

  setwd(cwd)
}
