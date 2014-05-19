#' Build a model using a data source from scratch.
#' 
#' @param key a string or list. If the former, there must be a
#'   file with name \code{model_stages} followed by \code{.r} so that syberia
#'   can read the model configurations.
#' @export
run_model <- function(key = get_cache('last_model') %||%
                      getOption('syberia.default_model'),
                      ..., fresh = FALSE, verbose = TRUE) {
  src_file <- NULL
  root <- NULL

  # This is a helper function that will be used to track which files are
  # loaded by a syberia model. Namely, the "source" function will get overwritten
  # by this one, which will keep track of whether any of the files have been
  # modified since last encountered by Syberia.
  syberiaStructure:::set_cache(TRUE, 'runtime/executing')
  syberiaStructure:::set_cache(FALSE, 'runtime/any_modified')
  on.exit(syberiaStructure:::set_cache(FALSE, 'runtime/executing'))
  #source <- local({
  #  any_modified <- FALSE
  #  function(file, ...) {
  #    provides <- list(source = source)
  #    if ('Ramd' %in% .packages()) provides$define <-
  #
  #    if (mock_define(
  #    resource <- syberia_resource(file, syberia_root(),
  #                                 provides = , ...)
  #    any_modified <<- any_modified || resource$modified
  #    list(value = resource$value(), invisible = TRUE)
  #  }
  #})

  # Used by syberiaStructure::syberia_resource
  syberiaStructure:::set_cache(parent.frame(), 'runtime/current_env')
  source <- syberiaStructure::source

  model_stages <- 
    #if (missing(key) && is.stagerunner(tmp <- active_runner())) tmp
    #if (missing(key)) get_cache('last_model')
    if (is.character(key)) {
      if (FALSE == (src_file <- normalized_filename(key))) {
        root <- tryCatch(syberia_root(key), error = function(e) NULL) %||% syberia_root()
        src_file <- syberia_models(pattern = key, root = root)[1]
        if (is.null(src_file) || is.na(src_file) || identical(src_file, FALSE))
          stop(pp("No file for model '#{key}'"))
      } else root <- syberia_root(src_file) # Cache syberia root
      message("Loading model: ", src_file)
      source(file.path(root %||% syberia_root(), 'models', src_file))$value
    }
    else if (is.list(key)) key
    else if (is.stagerunner(key)) key
    else stop("Invalid model key")
  
  if (is.null(src_file))
    src_file <- get_cache('last_model')
  if (is.null(root)) root <- syberia_root(src_file)

  display_file <- src_file
  src_file <- file.path(root, 'models', src_file)

  # Coalesce the stagerunner if model file updated
  coalesce_stagerunner <- FALSE
  if (missing(key) && is.character(key) &&
      is.character(tmp <- get_cache('last_model')) && key == tmp) {
    if (!is.null(old_timestamp <- get_registry_key(
        'cached_model_modified_timestamp', get_registry_dir(root)))) {
      new_timestamp <- file.info(src_file)$mtime
      if (new_timestamp > old_timestamp) coalesce_stagerunner <- TRUE
    }
  }

  set_cache(display_file, 'last_model')
  set_registry_key('cached_model_modified_timestamp',
                   file.info(src_file)$mtime, get_registry_dir(root))

  # TODO: Figure out how to integrate tests into this. We need something like:
  tests_file <- file.path(root, 'models', gsub('^[^/]+', 'test', display_file))
  testrunner <- NULL
  if (file.exists(tests_file)) {
    tests <- source(tests_file)$value
    testrunner <- stageRunner$new(new.env(), tests)
    testrunner$transform(function(fn) {
      require(testthat)
      force(fn)
      function(after) fn(cached_env, after)
    })
  }

  browser()
  if (coalesce_stagerunner) {
    stagerunner <- construct_stage_runner(model_stages)
    stagerunner$coalesce(get_cache('last_stagerunner'))
  } else if (!missing(key) || !is.stagerunner(stagerunner <- get_cache('last_stagerunner'))) {
    stagerunner <- construct_stage_runner(model_stages)
  }
  if (!is.null(testrunner)) stagerunner$overlay(testrunner, 'tests')

  message("Running model: ", display_file)
  out <- tryCatch(stagerunner$run(..., verbose = verbose),
           error = function(e) e)
  set_cache(stagerunner, 'last_stagerunner')

  if (inherits(out, 'simpleError'))
    stop(out$message)
  else out
}

