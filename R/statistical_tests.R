#' @importFrom foreach foreach %:% %dopar%
#' @importFrom doRNG %dorng%

#' @title Statistical test for differential association analysis
#' @description Perform statistical tests for scores generated using
#'   \code{dcScore}. Selects appropriate tests for the different methods used
#'   in computing scores. The exact test is selected based on the scoring method
#'   used and cannot be manually specified. Available tests include the z-test
#'   and permutation tests. Parallel computation supported for the permutation
#'   test.
#'
#' @param dcscores a matrix, the result of the \code{dcScore} function. The
#'   results should be passed as produced by the function and not modified in
#'   intermediate steps
#' @param emat a matrix, data.frame, ExpressionSet, SummarizedExperiment or
#'   DGEList. This should be the one passed to \code{dcScore}
#' @param condition a numeric, (with 1's and 2's representing a binary
#'   condition), a factor with 2 levels or a character representing 2
#'   conditions. This should be the one passed to \code{dcScore}
#' @param ... see details
#'
#' @details Ensure that the score matrix passed to this function is the one
#'   produced by \code{dcScore}. Any modification to the result matrix will
#'   cause this function to fail. This is intended as the test need to be
#'   performed on the entire score matrix, not subsets.
#'
#'   The appropriate test is chosen automatically based on the scoring method
#'   used. A z-test is performed for the z-score method while no tests are
#'   performed for DiffCoEx, EBcoexpress and FTGI. Permutation tests are
#'   performed for the remainder of methods by permutation sample labels.
#'   Statistics from a permutation are pooled such that statistics from all
#'   scores are used to evaluate a single observed score.
#'
#'   Additional method specific parameters can be supplied to the function when
#'   performing permutation tests. \code{B} specifies the number of permutations
#'   to be performed and defaults to 20.
#'
#'   If a cluster exists, computation in a permutation test will be performed in
#'   parallel (see examples).
#'
#' @name dcTest
#' @return a matrix, of p-values (or scores in the case of DiffCoEx and
#'   EBcoexpress) representing significance of differential associations.
#'   DiffCoEx will return scores as the publication specifies direct
#'   thresholding of scores and EBcoexpress returns posterior probabilities.
#' @seealso \code{\link{dcMethods}}, \code{\link{dcScore}}
#'
#' @examples
#' x <- matrix(rnorm(60), 2, 30)
#' cond <- rep(1:2, 15)
#' scores <- dcScore(x, cond, dc.method = 'mindy')
#' dcTest(scores, emat = x, condition = cond)
#'
#' \dontrun{
#' #running in parallel
#' num_cores = 2
#' cl <- parallel::makeCluster(num_cores)
#' doSNOW::registerDoSNOW(cl) #or doParallel
#' set.seed(36) #for reproducibility
#' dcTest(scores, emat = x, condition = cond, B = 100)
#' parallel::stopCluster(cl)
#' }
#'
#' @export
dcTest <- function(dcscores, emat, condition, ...) {
  if (!all(c('dc.method', 'call') %in% names(attributes(dcscores)))) {
    stop('Please ensure dcscores has not been modified')
  }

  dc.method = attr(dcscores, 'dc.method')
  pmat = do.call(methodmap[dc.method, 'testf'], list(quote(dcscores), quote(emat), quote(condition), ...))

  return(pmat)
}

z.test <- function(dcscores, ...) {
  #compute raw p-values
  pvals = pnorm(abs(dcscores), lower.tail = FALSE) * 2
  attributes(pvals) = attributes(dcscores)

  #add test type to attributes
  attr(pvals, 'dc.test') = 'two tailed z-test'

  return(pvals)
}

no.test <- function(dcscores, ...) {
  warning('No statistical test required')
  attr(dcscores, 'dc.test') = 'none'

  return(dcscores)
}

#vectorize networks - helper function convert scorematrix to a symmetric matrix then vector
mat2vec <- function(m) {
  m = pmax(m, t(m))
  v = m[upper.tri(m)]
  attr(v, 'feature.names') = rownames(m) #store names to enable reconstruction
  attr(v, 'mat.attrs') = attributes(m) #store names to enable reconstruction

  return(v)
}

vec2mat <- function(v) {
  sz = (1 + sqrt(1 + 8 * length(v))) / 2 #recompute size, quadratic solve
  m = matrix(NA, sz, sz)
  m[upper.tri(m)] = v
  m = t(m)
  m[upper.tri(m)] = v
  colnames(m) = rownames(m) = attr(v, 'feature.names')
  attributes(m) = attr(v, 'mat.attrs')

  return(m)
}

perm.test <- function(dcscores, emat, condition, B = 20) {
  obs = mat2vec(dcscores)

  #package requirements
  pckgs = c('dcanr')

  #perform permutation
  pvals = foreach(
    b = seq_len(B),
    .combine = function(...) {mapply(sum, ...)},
    .multicombine = TRUE,
    .inorder = FALSE,
    .packages = pckgs
  ) %dorng% {
    #shuffle condition and recalculate scores
    env = new.env()
    #convert conditions to numeric
    condition = as.numeric(as.factor(condition))
    assign('emat', emat, envir = env)
    assign('condition', sample(condition, length(condition)), envir = env)
    permsc = eval(attr(dcscores, 'call'), envir = env)
    permsc = mat2vec(permsc)

    #count elements greater than obs
    permsc = abs(permsc)
    permsc = permsc[!(is.na(permsc) || is.infinite(permsc))]
    permcounts = vapply(abs(obs), function(x) sum(permsc > x), 0)
    return(c(permcounts, length(permsc)))
  }

  #p-values
  N = pvals[length(pvals)]
  pvals = pvals[-(length(pvals))] / N
  attributes(pvals) = attributes(obs)
  pvals = vec2mat(pvals)
  attr(pvals, 'dc.test') = 'permutation'

  return(pvals)
}
