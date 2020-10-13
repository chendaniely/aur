library(magrittr)
library(stringr)

get_pkgbuild_name_version <- function(url) {
  ## Read pkgbuild file from AUR
  pth_pkgfile <- tempfile()

  download.file(url, destfile = pth_pkgfile)

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

  return(
    list(
      pkgname = pkgname,
      pkgversion = pkgversion
    )
  )
}

clone_from_aur <- function(remote_url, save_pth, git_credentials) {
  #aur_git_pth <- paste(tempdir(), 'rstudio-desktop-preview-bin', sep = '/')
  #aur_git_pth <- aur_git_pth
  #remote_url <- "ssh://aur@aur.archlinux.org/rstudio-desktop-daily-bin.git"
  #remote_url <- "https://aur.archlinux.org/rstudio-desktop-daily-bin.git"

  if (fs::dir_exists(save_pth)) {fs::dir_delete(save_pth)}

  #git_credentials <- git_credentials

  git2r::clone(url = remote_url,
               local_path = save_pth,
               credentials = git_credentials)

}

# https://s3.amazonaws.com/rstudio-ide-build/desktop/bionic/amd64/rstudio-1.3.1081-amd64.deb

update_pkgbuild_file <- function(local_clone_pth, deb_url, deb_version) {
  clone_pkgbuild_pth <- paste(local_clone_pth, "PKGBUILD", sep = "/")

  clone_pkgbuild <- readLines(clone_pkgbuild_pth)

  pkgver_line <- clone_pkgbuild[[11]]
  sha256sum_line <- clone_pkgbuild[[25]]

  stopifnot(stringr::str_starts(pkgver_line, "pkgver="))
  stopifnot(stringr::str_starts(sha256sum_line, "sha256sums_x86_64="))

  deb_pth <- paste(local_clone_pth, fs::path_file(deb_url), sep = "/")

  download.file(deb_url, destfile = deb_pth)

  #sha256 <- digest::digest(xenial_deb_pth, algo = "sha256")
  sha256 <- system2("sha256sum", deb_pth, stdout = TRUE) %>%
    stringr::str_split_fixed(" ", n = 2) %>%
    .[,1]

  new_pkgver_line <- stringr::str_replace(pkgver_line,
                                          pattern = "(?<=\\=).*",
                                          replacement = deb_version)
  new_sha256sum_line <- stringr::str_replace(sha256sum_line,
                                             pattern = "(?<=\\(').*(?='\\))", # between the round brackets
                                             replacement = sha256)

  clone_pkgbuild[[11]] <- new_pkgver_line
  clone_pkgbuild[[25]] <- new_sha256sum_line

  writeLines(text = clone_pkgbuild, con = clone_pkgbuild_pth)
}

mksrcinfo <- function(local_clone_pth) {
  clone_pkgbuild_pth <- paste(local_clone_pth, "PKGBUILD", sep = "/")
  clone_srcinfo_pth <- paste(local_clone_pth, ".SRCINFO", sep = "/")
  .old_wd <- getwd()

  setwd(local_clone_pth)
  system2("makepkg",
          args = c("--printsrcinfo", clone_pkgbuild_pth),
          stdout = clone_srcinfo_pth)
  print(fs::dir_ls(all = TRUE))
  print(git2r::status())
  print(system2("git",
                c("diff", "HEAD", "--no-ext-diff", "--unified=0", "--exit-code", "-a", "--no-prefix")))
  setwd(.old_wd)
}

git_add_commit_push <- function(local_clone_path,
                                message,
                                git_credentials,
                                push = FALSE) {
  .old_wd <- getwd()

  setwd(local_clone_path)
  print(git2r::status())

  git2r::add(repo = '.', path = c("PKGBUILD", ".SRCINFO"))
  git2r::commit(message = message)

  print(git2r::status())

  if (push) {git2r::push(credentials = git_credentials)}

  setwd(.old_wd)
}
