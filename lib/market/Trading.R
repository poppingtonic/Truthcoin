
### Trading Protocol and Market Maker ###
# try(setwd("~/GitHub/Truthcoin/lib"))
source(file="market/Markets.r")

#Global Parameter
FeeRate <<- .01


## Simple Market Info ##
ShowPrices <- function(ID) {
  #Takes a Market and ID and returns the current market price.
  S <- exp(Markets[[ID]]$Shares/Markets[[ID]]$B)
  return(S/sum(S))
}


QueryMove <- function(ID,State,P) {
  #How many shares would I need to buy of'ID'-'State' to move the probability to 'P'?
  S <- exp(Markets[[ID]]$Shares/Markets[[ID]]$B)
  Sstar <- Markets[[ID]]$B* ( log(P/(1-P)) + log(sum(S[-State])) )
  Marginal <- Sstar -Markets[[ID]]$Shares[State]
  return(Marginal)
}


QueryCost <- function(ID,State,S) {
  #What price will the market-maker demand for a purchase of S shares?  
  B <- Markets[[ID]]$B
  
  #Original Case
  S0 <- Markets[[ID]]$Shares
  LMSR <- B*log(sum(exp(S0/B)))
  
  #Proposed Adjustment
  S1 <- S0;  S1[State] <- S1[State] + S
  LMSR2 <- B*log(sum(exp(S1/B)))
  
  return( LMSR2-LMSR )
}


QueryMoveCost <- function(ID,State,P) {
  #How much would it cost to set the probability to P?
  NewS <- QueryMove(ID,State,P) 
  return( QueryCost(ID,State, NewS ) )
}



## User Accounts ##
Users <- vector("list",length=0) #Critical Step...creates (blank) marketplace. Would erase the existing marketplace if called twice.

CreateAccount <- function(Name,Qfunds) {
  #Creates an account filled with money.
  #Obviously, this is a crucial step which will require (!) verification of Bitcoin payments, an X-confirmation delay, etc. For testing we allow unconstrained (free/infinite) cash.
  #These accounts have simple toy names, actual accounts will probably be the bitcoin addresses themselves.
  Users[[Name]]$Cash <<- Qfunds
}



## Buying and Selling Shares ##

Buy <- function(uID,ID,State,P,Verbose=TRUE) {
  
  #Calculate Required Cost
  BaseCost <- QueryMoveCost(ID,State,P) #trade cost assuming no fees
  Fee <- BaseCost*FeeRate               #fees for buying only (global parameter set at top)
  TotalCost <- BaseCost + Fee           #Total cost including Fee

  MarginalShares <- QueryMove(ID,State,P)
  if(MarginalShares<0) return("Price already exceeds target. Sell shares or buy a Mutually Exclusive State (MES).")
  if(Verbose) { print(paste("Calulating Required Shares...",MarginalShares)); print(paste("Determining Cost of Trade...",BaseCost)); print(paste("Fee:",Fee)) }
  
  #Reduce Funds, add Shares
  if( Users[[uID]]$Cash < TotalCost) return("Insufficient Funds")
  Users[[uID]]$Cash <<-  Users[[uID]]$Cash - TotalCost 
  OldShares <- Users[[uID]][[ID]][[paste("State",State,sep="")]] ; if(is.null(OldShares)) OldShares <- 0
  Users[[uID]][[ID]][[paste("State",State,sep="")]] <<- OldShares + MarginalShares
    
  #Credit Funds, add Shares
  Markets[[ID]]$Balance <<-  Markets[[ID]]$Balance + BaseCost
  Markets[[ID]]$FeeBalance <<-  Markets[[ID]]$FeeBalance + Fee
  Markets[[ID]]$Shares[State] <<- Markets[[ID]]$Shares[State] + MarginalShares  
  
  if(Verbose) print(paste("Bought",MarginalShares,"for",TotalCost,"."))
  return(c(MarginalShares,TotalCost))
}

Sell <- function(uID,ID,State,P,Verbose=TRUE) {
  #Calculate Required Cost
  Cost <- QueryMoveCost(ID,State,P)
  MarginalShares <- QueryMove(ID,State,P)
  if(MarginalShares>0) return("Price already below target. Buy shares or sell a Mutually Exclusive State (MES).")
  if(Verbose) { print("Calulating Required Shares..."); print(MarginalShares); print("Determining Cost of Trade..."); print(Cost) }
  
  #Reduce shares, add Funds
  OldShares <- Users[[uID]][[ID]][[paste("State",State,sep="")]]
  if(OldShares<(-1*MarginalShares)) return("Insufficient Shares") #Remember, shares are negative.
  Users[[uID]][[ID]][[paste("State",State,sep="")]] <<- OldShares + MarginalShares 
  Users[[uID]]$Cash <<-  Users[[uID]]$Cash - Cost #Cost is also negative
  
  #Remove Funds and Shares from Market
  Markets[[ID]]$Balance <<-  Markets[[ID]]$Balance + Cost  
  Markets[[ID]]$Shares[State] <<- Markets[[ID]]$Shares[State] + MarginalShares 
  
  if(Verbose) print(paste("Sold",-1*MarginalShares,"for",-1*Cost,"."))
  return(c(MarginalShares,Cost))
}

## NOT DONE !!!

FinalSell <- function(uID,ID,State,S,Verbose=TRUE) {
  #This function takes over after the event's state has been determined, and all shares are either worth zero or the unit price.
  Judged <- BlockChain[[length(BlockChain)]]$Jmatrix
  ContractState <- -2
  ContractState <- try(Judged[Judged$Contract==ID,2])
  if(Verbose) print(paste("Determined State of this Market:", ContractState))
  
  #Which shares are valuable?
  if(ContractState<0) return("You cannot sell using this function until there is a consensus about the outcome.") 
  if(State!=ContractState) return("Shares of this state have value 0.") 
  OldShares <- Users[[uID]][[ID]][[paste("State",State,sep="")]]
  
  MarginalShares <- S*-1 #Users are expected to enter +3 if they wish to sell 3 shares, ie marginally change shares by -3.
  Cost <- MarginalShares # All shares have value 1, so this identiy holds.
    
  #Reduce shares, add Funds
  Users[[uID]][[ID]][[paste("State",State,sep="")]] <<- OldShares + MarginalShares #MarginalShares are negative
  Users[[uID]]$Cash <<-  Users[[uID]]$Cash - Cost #Cost is negative
  
  #Remove Funds and Shares from Market
  Markets[[ID]]$Balance <<-  Markets[[ID]]$Balance + Cost  
  Markets[[ID]]$Shares[State] <<- Markets[[ID]]$Shares[State] + MarginalShares 
  
  if(Verbose) print(paste("FinalSold",-1*MarginalShares,"for",-1*Cost,"."))
  return(c(MarginalShares,Cost))
}  
