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
