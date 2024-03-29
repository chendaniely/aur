library(magrittr)
library(stringr)

get_pkgbuild_name_version <- function(url) {
  ## Read pkgbuild file from AUR
  pth_pkgfile <- tempfile()

  download.file(url, destfile = pth_pkgfile)

  pkgbuild <- readLines(pth_pkgfile)

  pkgversion <- pkgbuild[stringr::str_detect(pkgbuild, "pkgname=|pkgver=|pkgver_url=")]

  stopifnot(length(pkgversion) == 3)

  pkgname <-  pkgversion[[1]] %>%
    stringr::str_split_fixed(pattern = "=", n = 2) %>%
    .[,2]

  pkgver_aur <- pkgversion[[2]] %>%
    stringr::str_split_fixed(pattern = "=", n = 2) %>%
    .[,2] %>%
    stringr::str_trim()

  pkgver_url <- pkgversion[[3]] %>%
    stringr::str_split_fixed(pattern = "=", n = 2) %>%
    .[,2] %>%
    stringr::str_trim()

  return(
    list(
      pkgname = pkgname,
      pkgversion = pkgver_aur,
      pkgver_url = pkgver_url
    )
  )
}

clone_from_aur <- function(remote_url, save_pth, git_credentials) {
  #aur_git_pth <- paste(tempdir(), 'rstudio-desktop-preview-bin', sep = '/')
  #aur_git_pth <- aur_git_pth
  #remote_url <- "ssh://aur@aur.archlinux.org/rstudio-desktop-daily-bin.git"
  #remote_url <- "https://aur.archlinux.org/rstudio-desktop-daily-bin.git"

  #if (fs::dir_exists(save_pth)) {fs::dir_delete(save_pth)}

  if (fs::dir_exists(save_pth)) {
    fs::dir_delete(save_pth)
    fs::dir_create(save_pth)
  }

  system(glue::glue("git clone {remote_url} {save_pth}"))

  #git_credentials <- git_credentials

  # git2r::clone(url = remote_url,
  #              local_path = save_pth,
  #              credentials = git_credentials)

}

# https://s3.amazonaws.com/rstudio-ide-build/desktop/bionic/amd64/rstudio-1.3.1081-amd64.deb

update_pkgbuild_file <- function(local_clone_pth, deb_url, deb_version,
                                 pkgver_line_num=11L,
                                 pkgver_url_line_num=12L,
                                 sha256sum_line_num=26L) {
  #local_clone_pth <- aur_git_pth
  #deb_url <- rstudio_desktop_preview_bionic$s3_url
  #deb_version <- rstudio_desktop_preview_bionic$version

  clone_pkgbuild_pth <- paste(local_clone_pth, "PKGBUILD", sep = "/")

  clone_pkgbuild <- readLines(clone_pkgbuild_pth)

  pkgver_line <- clone_pkgbuild[[pkgver_line_num]]
  pkgver_url_line <- clone_pkgbuild[[pkgver_url_line_num]]
  sha256sum_line <- clone_pkgbuild[[sha256sum_line_num]]

  stopifnot(stringr::str_starts(pkgver_line, "pkgver="))
  stopifnot(stringr::str_starts(pkgver_url_line, "pkgver_url="))
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
  new_pkgver_url_line <- stringr::str_replace(pkgver_url_line,
                                              pattern = "(?<=\\=).*",
                                              replacement = deb_version) %>%
    stringr::str_replace(pattern = "\\+", replacement = "-")
  new_sha256sum_line <- stringr::str_replace(sha256sum_line,
                                             pattern = "(?<=\\(').*(?='\\))", # between the round brackets
                                             replacement = sha256)

  clone_pkgbuild[[pkgver_line_num]] <- new_pkgver_line
  clone_pkgbuild[[pkgver_url_line_num]] <- new_pkgver_url_line
  clone_pkgbuild[[sha256sum_line_num]] <- new_sha256sum_line

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

  if (push) {
    system(glue::glue("git push origin master"))
    #git2r::push(credentials = git_credentials)
  }

  setwd(.old_wd)
}
