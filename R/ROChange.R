ROChange <- structure(function # ROC curve for changepoints
### Compute a Receiver Operating Characteristic curve for a penalty
### function.
(models,
### data.frame describing the number of incorrect labels as a function
### of log(lambda), with columns min.log.lambda, max.log.lambda, fp,
### fn, possible.fp, possible.fn, etc. This can be computed via
### labelError(modelSelection(...), ...)$model.errors -- see examples.
  predictions,
### data.frame with a column named pred.log.lambda, the predicted
### log(penalty) value for each segmentation problem.
  problem.vars=character()
### character: column names used to identify data set / segmentation
### problem. 
){
  possible.fp <- possible.fn <- min.log.lambda <- fp <- fn <- thresh <-
    log.lambda <- pred.log.lambda <- errors <- FPR <- tp <- TPR <-
      error.percent <- min.thresh <- max.thresh <- max.log.lambda <- 
        next.min <- NULL
### The code above is to avoid CRAN NOTEs like
### ROChange: no visible binding for global variable
  if(!(
    is.character(problem.vars) &&
      0 < length(problem.vars) &&
      !is.na(problem.vars)
    )){
    stop("problem.vars should be a character vector of column names (IDs for predictions and models)")
  }
  exp.cols <- c(
    "fp", "possible.fp", "fn", "possible.fn", "errors", "labels",
    problem.vars, "min.log.lambda", "max.log.lambda")
  if(!(
    is.data.frame(models) &&
      all(exp.cols %in% names(models))
    )){
    stop("models should have columns ", paste(exp.cols, collapse=", "))
  }
  for(col.name in exp.cols){
    if(any(is.na(models[[col.name]]))){
      stop(col.name, " should not be NA")
    }
  }
  if(!(
    is.data.frame(predictions) &&
    0 < nrow(predictions) &&
    "pred.log.lambda" %in% names(predictions)
  )){
    stop("predictions should be a data.frame with at least one row and a column named pred.log.lambda")
  }
  pred <- data.table(predictions)
  err <- data.table(models)[pred, on=problem.vars]
  setkeyv(err, c(problem.vars, "min.log.lambda"))
  err.missing <- err[is.na(labels)]
  if(nrow(err.missing)){
    print(err.missing)
    stop("some predictions do not exist in models")
  }
  min.max.not.Inf <- err[, list(
    min=min(min.log.lambda),
    max=max(max.log.lambda)
  ), by=problem.vars][-Inf < min | max < Inf]
  if(nrow(min.max.not.Inf)){
    print(min.max.not.Inf)
    stop("for every problem, the smallest min.log.lambda should be -Inf, and the largest max.log.lambda should be Inf")
  }
  err[, next.min := c(min.log.lambda[-1], Inf), by=problem.vars]
  min.max.inconsistent <- err[next.min != max.log.lambda]
  if(nrow(min.max.inconsistent)){
    print(min.max.inconsistent)
    stop("max.log.lambda should be equal to the next min.log.lambda")
  }
  for(col.name in c("labels", "possible.fp", "possible.fn")){
    possible.ranges <- err[, {
      x <- .SD[[col.name]]
      list(
        min=min(x),
        max=max(x)
      )}, by=problem.vars]
    possible.inconsistent <- possible.ranges[min != max]
    if(nrow(possible.inconsistent)){
      print(possible.inconsistent)
      stop(
        col.name,
        " should be constant for each problem")
    }
  }
  negative <- err[possible.fp<0 | possible.fn<0 | labels<0]
  if(nrow(negative)){
    print(negative)
    stop("possible.fn/possible.fp/labels should be non-negative")
  }
  possible.name.vec <- c(
    errors="labels",
    fp="possible.fp",
    fn="possible.fn")
  for(err.name in names(possible.name.vec)){
    poss.name <- possible.name.vec[[err.name]]
    poss.num <- err[[poss.name]]
    err.num <- err[[err.name]]
    out.of.range <- err[poss.num < err.num | err.num < 0]
    if(nrow(out.of.range)){
      print(out.of.range)
      stop(
        err.name,
        " should be in [0,",
        poss.name,
        "]")
    }
  }
  first.dt <- err[max.log.lambda==Inf]
  total.dt <- first.dt[, list(
    labels=sum(labels),
    possible.fp=sum(possible.fp),
    possible.fn=sum(possible.fn))]
  if(total.dt$possible.fp==0){
    stop("no negative labels")
  }
  if(total.dt$possible.fn==0){
    stop("no positive labels")
  }
  thresh.dt <- err[order(-min.log.lambda), {
    fp.diff <- diff(fp)
    fp.change <- fp.diff != 0
    fn.diff <- diff(fn)
    fn.change <- fn.diff != 0
    fp.dt <- if(any(fp.change))data.table(
      log.lambda=min.log.lambda[c(fp.change, FALSE)],
      fp=as.numeric(fp.diff[fp.change]),
      fn=0)
    fn.dt <- if(any(fn.change))data.table(
      log.lambda=min.log.lambda[c(fn.change, FALSE)],
      fp=0,
      fn=as.numeric(fn.diff[fn.change]))
    ##browser(expr=sample.id=="McGill0322")
    rbind(fp.dt, fn.dt)
  }, by=problem.vars]
  pred.with.thresh <- thresh.dt[pred, on=problem.vars, nomatch=0L]
  pred.with.thresh[, thresh := log.lambda - pred.log.lambda]
  uniq.thresh <- pred.with.thresh[, list(
    fp=sum(fp),
    fn=sum(fn)
  ), by=thresh]
  interval.dt <- uniq.thresh[order(-thresh), data.table(
    total.dt,
    min.thresh=c(thresh, -Inf),
    max.thresh=c(Inf, thresh),
    fp=cumsum(c(sum(first.dt$fp), fp)),
    fn=sum(first.dt$fn)+cumsum(c(0, fn)))]
  interval.dt[, errors := fp+fn]
  interval.dt[, FPR := fp/possible.fp]
  interval.dt[, tp := possible.fn - fn]
  interval.dt[, TPR := tp/possible.fn]
  interval.dt[, error.percent := 100*errors/labels]
  roc.polygon <- interval.dt[, {
    has11 <- FPR[.N]==1 & TPR[.N]==1
    has00 <- FPR[1]==0 & TPR[1]==0
    list(
      FPR=c(if(!has00)0, FPR, if(!has11)1, 1),
      TPR=c(if(!has00)0, TPR, if(!has11)1, 0)
      )
  }]
  list(
    roc=interval.dt,
    thresholds=rbind(
      data.table(
        threshold="predicted",
        interval.dt[min.thresh <= 0 & 0 <= max.thresh, ]),
      data.table(threshold="min.error", interval.dt[which.min(errors), ])),
    auc.polygon=roc.polygon,
    auc=roc.polygon[, geometry::polyarea(FPR, TPR)]
    )
### list of results describing ROC curve: roc is a data.table with one
### row for each point on the ROC curve; thresholds is the two rows of
### roc which correspond to the predicted and minimal error
### thresholds; auc.polygon is a data.table with one row for each
### vertex of the polygon used to compute AUC; auc is the numeric Area
### Under the ROC curve, actually computed via geometry::polyarea as
### the area inside the auc.polygon.
}, ex=function(){

  library(penaltyLearning)
  data(neuroblastomaProcessed, envir=environment())
  ## Get incorrect labels data for one profile.
  pid <- 11
  pro.errors <- neuroblastomaProcessed$errors[profile.id==pid,]
  ## Get the feature that corresponds to the BIC penalty = log(n),
  ## meaning log(penalty) = log(log(n)).
  chr.vec <- paste(c(1:4, 11, 17))
  pid.names <- paste0(pid, ".", chr.vec)
  BIC.feature <- neuroblastomaProcessed$feature.mat[pid.names, "log2.n"]
  pred <- data.table(pred.log.lambda=BIC.feature, chromosome=chr.vec)
  result <- ROChange(pro.errors, pred, "chromosome")
  library(ggplot2)
  ## Plot the ROC curves.
  ggplot()+
    geom_path(aes(FPR, TPR), data=result$roc)+
    geom_point(aes(FPR, TPR, color=threshold), data=result$thresholds, shape=1)
  
  ## Plot the number of incorrect labels as a function of threshold.
  ggplot()+
    geom_segment(aes(
      min.thresh, errors,
      xend=max.thresh, yend=errors),
      data=result$roc)+
    geom_point(aes((min.thresh+max.thresh)/2, errors, color=threshold),
               data=result$thresholds,
               shape=1)+
    xlab("log(penalty) constant added to BIC penalty")

})

