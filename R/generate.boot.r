#' Generate and calculate bootstrap means for all clusters
#'
#' @param variants: data frame of variants with cluster assignments and VAF
#' of samples. Columns are c('cluster', 'sample1vaf', 'sample2vaf', ...,
#' 'sample1depth', 'sample2depth', ....). If possible, reduce input file to only necessary columns. For unweighted resampling, columns will be assumed to be VAF columns if not explicitly specified.
#' @param cluster.col.name: name of column containing cluster information. Must
#' be specified. Default: 'cluster'.
#' @param vaf.col.names: names of columns containing VAFs for each sample.
#' Default NULL. If weighted=FALSE and no VAF columns are specified, every
#' column except the cluster column will be treated as VAF columns. 
#' @param depth.col.names: names of columns containing depth for each sample.
#' Default NULL. If weighted=TRUE, depth column names must all be specified.
#' @param vaf.in.percent: If TRUE, VAFs will be converted to proportions
#' between 0 and 1. Default TRUE.
#' @param num.boots: Number of times to resample. Default 1000.
#' @param bootstrap.model: specifies the statistical model used in bootstrap
#' resampling. Model can be normal, normal-truncated, beta, binomial,
#' beta-binomial, or non-parametric. Default: 'non-parametric'.
#' @param weighted: If TRUE, weights variants proportionally to read count.
#' If TRUE, VAF and depth cluster columns must be specified. Default: FALSE.
#' @param zero.sample: The sample of zero vaf (to use to compare with other
#' clusters to determine if the cluster should be considered zero VAF, and
#' not included in the models)

#Last update: Steven Mason Foltz 2015-03-23
#Original by Ha X. Dang
#SMF added weighted parametric bootstrap functionality

generate.boot <- function(variants,
                          cluster.col.name='cluster',
                          vaf.col.names=NULL,
                          depth.col.names=NULL,
                          vaf.in.percent=TRUE,
                          num.boots=1000,
                          bootstrap.model='non-parametric',
                          weighted=FALSE,
                          zero.sample=NULL){

    #check that the model is not NULL
    if(is.null(bootstrap.model)){
        stop("User must specify statistical model for parametric bootstrap resampling. Model can be 'normal', 'normal-truncated', 'beta', 'binomial', 'beta-binomial', or 'non-parametric'.\n")
    }
    if(!(bootstrap.model %in% c("normal","normal-truncated", "beta", "binomial",
      "beta-binomial", "non-parametric"))){
        stop("User must specify statistical model for parametric bootstrap resampling. Model can be 'normal', 'normal-truncated', 'beta', 'binomial', 'beta-binomial', or 'non-parametric'.\n")
    }

    #check that the weighted parameter is logical
    if(!is.logical(weighted)){
        stop("'weighted' parameter must be TRUE or FALSE. Default is FALSE.\n")
    }

    #check the cluster input variable
    if(is.null(cluster.col.name)){
        stop("Input error: cluster column name cannot be null.\n")
    }
    if(!(cluster.col.name %in% colnames(variants))){
        stop("Input error: cluster column name does not appear in variants file.\n")
    }

    #check VAF, and count column specifications
    if(!is.null(vaf.col.names) | !is.null(depth.col.names)){
        #checks that input column names appear in variants file.
        if(!is.null(vaf.col.names) & !all(vaf.col.names %in%
          colnames(variants))){
            stop("Input error: not all specified VAF column names appear in variants file.\n")
        }
        if(weighted & !is.null(depth.col.names) & !all(depth.col.names %in%
          colnames(variants))){
            stop("Input error: not all specified depth column names appear in variants file.\n")
        }
    }

    #assigns names to vaf.col.names as needed
    if(weighted){
        if(is.null(vaf.col.names) | is.null(depth.col.names)){
            stop("Input error: for weighted resampling, please specify all VAF and depth column names.\n")
        }
        #check that VAF and depth column names are same length if depth not null
        if(length(vaf.col.names) != length(depth.col.names)){
            stop("Input error: different number of VAF and depth columns.\n")
        }
        if(any(vaf.col.names %in% depth.col.names)){
            stop("Input error: one or more VAF and depth column names overlap.\n")
        }
    }
    else{ #not weighted
        if(is.null(vaf.col.names)){
            vaf.col.names = setdiff(colnames(variants),cluster.col.name)
            cat("Note: VAF columns assumed to be every column except specified cluster. If depth columns were specified, they were ignored.\n")
        }
    }

    #if no cluster or no sample provided, return NULL
    clusters = unique(variants[[cluster.col.name]])
    num.clusters = length(clusters)
    num.samples = length(vaf.col.names)
    if (num.samples == 0 || num.clusters == 0){return(NULL)}
    if (vaf.in.percent){
        variants[,vaf.col.names] = variants[,vaf.col.names]/100.00
        cat("Note: all VAFs were divided by 100 to convert from percentage to proportion.\n")
    }

    #check to make sure all VAF columns have values between 0-1
    if(any(variants[,vaf.col.names] < 0 | variants[,vaf.col.names] > 1)){
        stop("Input error: some VAFs not between 0 and 1.\n")
    }

    cat(paste0('Generating ',bootstrap.model,' boostrap samples...'))
    boot.means = NULL

    #make separate data frame for each cluster
    v = list()
    for (cl in clusters){
        v1 = variants[variants[[cluster.col.name]]==cl, c(vaf.col.names,
        depth.col.names)]
        v[[as.character(cl)]] = v1
    }

    # generate bootstrap samples for each cluster, each sample
    num.variants.per.cluster = table(variants[[cluster.col.name]])
    #print(num.variants.per.cluster)

    boot.means = list()
    clusters = as.character(clusters)
    zeros = c()
    for (col.name in 1:length(vaf.col.names)){
        vaf.col.name = vaf.col.names[col.name]
        #cat('Booting sample: ', vaf.col.name, '\n')
        sample.boot.means = matrix(NA, nrow=num.boots, ncol=num.clusters)
        colnames(sample.boot.means) = clusters
        rownames(sample.boot.means) = seq(1, num.boots)

        for (cl in clusters){
            boot.size = num.variants.per.cluster[cl]
            vafs = v[[cl]][[vaf.col.name]]

            # learn zero samples from data,
            # if a cluster has median VAF = 0, consider
            # it as a sample generated from true VAF = 0
            if (median(vafs)==0){zeros = c(zeros, vafs)}

            #find the mean and standard deviation of the cluster
            #mean and sd are used as parameters in bootstrapping
            if(weighted){ #weighted sum and sd
                depth.col.name = depth.col.names[col.name]
                depth = v[[cl]][[depth.col.name]]
                this.mean = (1/sum(depth))*sum(vafs*depth)
                this.sd = sqrt((sum(depth)/(sum(depth)^2-sum(depth^2)))*
                sum(depth*(vafs-this.mean)^2))
            }
            else{ #not weighted
                depth = rep(1,boot.size)
                this.mean = mean(vafs)
                this.sd = sd(vafs)
            }

            #uses normal - could produce values below 0 or above 1 (bad)
            if(bootstrap.model == "normal"){
                for (b in 1:num.boots){
                    #use mean and standard deviation as normal MLEs
                    s.mean = mean(rnorm(n=boot.size,mean=this.mean,sd=this.sd))
                    sample.boot.means[b,cl] = s.mean
                }
            }

            #uses zero-one truncated Normal distribution
            else if(bootstrap.model == "normal-truncated"){
                library(truncnorm) #use truncnorm library
                for (b2 in 1:num.boots){ #b2 since b in rtruncnorm()
                    #use mean and standard deviation as normal MLEs
                    s.mean = mean(rtruncnorm(n=boot.size,a=0,b=1,mean=this.mean,
                        sd=this.sd))
                    sample.boot.means[b2,cl] = s.mean
                }
            }

            else if(bootstrap.model == "beta"){
                #use mean and sd to calculate alpha and beta (method of moments)
                m = this.mean; var = this.sd^2
                alpha = m*((m-m*m)/var-1); beta = (1-m)*((m-m*m)/var-1)
                for(b in 1:num.boots){
                    s.mean = mean(rbeta(n=boot.size, shape1=alpha, shape2=beta))
                    sample.boot.means[b,cl] = s.mean
                }
            }

            else if(bootstrap.model == "binomial"){
                #use mean to define probability of success in 100 trials
                for(b in 1:num.boots){
                    s.mean = mean(rbinom(n=boot.size,size=100,prob=this.mean))
                    sample.boot.means[b,cl] = s.mean/100
                }
            }

            else if(bootstrap.model == "beta-binomial"){
                #binomial with probability drawn from a beta distribution
                #use mean and sd to calculate alpha and beta (method of moments)
                m = this.mean; var = this.sd^2
                alpha = m*((m-m*m)/var-1); beta = (1-m)*((m-m*m)/var-1)
                for(b in 1:num.boots){
                    beta.probs = rbeta(n=boot.size,shape1=alpha,shape2=beta)
                    s.mean = mean(rbinom(n=boot.size,size=100,prob=beta.probs))
                    sample.boot.means[b,cl] = s.mean/100
                }
            }

            else { #if(bootstrap.model == "non-parametric"){
                #cat('Booting cluster: ', cl, 'boot.size=', boot.size, '\n')
                for (b in 1:num.boots){
                    s.mean = mean(sample(v[[cl]][[vaf.col.name]], boot.size,
                      replace=T, prob=depth))
                    sample.boot.means[b, cl] = s.mean
                }
            }
        }
    boot.means[[vaf.col.name]] = sample.boot.means
    }

    #generate bootstrap means for zero sample
    if (is.null(zero.sample)){
        zero.sample = zeros
    }

    if (length(zero.sample) > 0){
        zero.sample.boot.means = rep(NA, num.boots)
        zero.sample.boot.size = length(zero.sample)
        for (b in 1:num.boots){
            s.mean = mean(sample(zero.sample, zero.sample.boot.size, replace=T))
            zero.sample.boot.means[b] = s.mean
        }
        boot.means$zero.means = zero.sample.boot.means
    }
    cat(" done.\n")
    return(boot.means)
}