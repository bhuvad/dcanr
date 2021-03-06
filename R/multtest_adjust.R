#' @include statistical_tests.R
NULL

#' @title Adjust for multiple testing in differential association analysis
#' @description Adjust for multiple hypothesis testing after performing
#'   statistical tests  using \code{dcTest}. This can be performed using a
#'   method provided by the users. \code{p.adjust} is used by default.
#'
#' @param dcpvals a matrix, the result of the \code{dcTest} function. The
#'   results should be passed as produced by the function and not modified in
#'   intermediate steps
#' @param f a function, the function to be used for adjustment. \code{p.adjust}
#'   from the \code{stats} package is the default with the specific adjustment
#'   method 'fdr' used. The range of available methods can be accessed using
#'   \code{p.adjust.methods}. Custom functions should accept a numeric vector of
#'   p-values as the first argument
#' @param ... additional parameters to the adjustment function such as
#'   \code{method}
#'
#' @details Ensure that the p-value matrix passed to this function is the one
#'   produced by \code{dcTest}. Any modification to the result matrix will
#'   result in failure of the function.
#'
#'   This method applies the adjustment method only to one triangle of the
#'   matrix to ensure adjustment is not performed for duplicated tests
#'   (symmetric matrix). As results from the DiffCoEx and EBcoexpress do not
#'   produce p-values, this method does not change anything thereby returning
#'   the original matrix.
#'
#' @name dcAdjust
#' @return a matrix, of adjusted p-values (or scores in the case of DiffCoEx and
#'   EBcoexpress) representing significance of differential associations.
#' @seealso \code{\link{dcTest}} \code{\link[stats]{p.adjust}}
#'
#' @examples
#' x <- matrix(rnorm(60), 2, 30)
#' cond <- rep(1:2, 15)
#' zscores <- dcScore(x, cond)
#' pvals <- dcTest(zscores, emat = x, condition = cond)
#' dcAdjust(pvals, p.adjust, method = 'fdr')
#'
#' @export
dcAdjust <- function(dcpvals, f = stats::p.adjust, ...) {
  if (!all(c('dc.test', 'dc.method') %in% names(attributes(dcpvals)))) {
    stop('Please ensure dcpvals has not been modified')
  }

  if (!methodmap[attr(dcpvals, 'dc.method'), 'adjust']) {
    warning('No adjustment performed')
    return(dcpvals)
  }

  #convert to vector (single triangle) and adjust p-values
  pvec = mat2vec(dcpvals)
  if (identical(f, p.adjust)) {
    #allow handling of excess arguments
    f = function(p, method = 'fdr', n = length(p), ...) {
      return(p.adjust(p, method, n))
    }
  }
  adjp = do.call(f, args = c(list(quote(pvec)), list(...)))
  attributes(adjp) = attributes(pvec)

  #convert back to matrix
  adjmat = vec2mat(adjp)

  #modify dc.test attribute
  attr(adjmat, 'dc.test') = paste(attr(adjmat, 'dc.test'), '(adj)')

  return(adjmat)
}
