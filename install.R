# Installs the CRAN packages this project needs into ./.Rlib, leaving the system library untouched.
pkgs <- c("ggplot2", "sandwich", "lmtest", "testthat", "strucchange", "jsonlite", "zoo", "patchwork", "scales")
dir.create(".Rlib", showWarnings = FALSE)
.libPaths(c(normalizePath(".Rlib"), .libPaths()))
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) install.packages(missing, lib = ".Rlib", repos = "https://cloud.r-project.org")
cat("All packages available:", all(pkgs %in% rownames(installed.packages())), "\n")
