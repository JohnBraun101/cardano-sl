{-# LANGUAGE RecursiveDo         #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

-- | Launcher of full node or simple operations.

module Pos.Launcher
       ( NodeParams (..)
       , getCurTimestamp
       , runNode
       , runNodeReal
       , submitTx
       , submitTxReal
       ) where

import           Control.TimeWarp.Logging (logInfo)
import           Control.TimeWarp.Rpc     (NetworkAddress)
import           Control.TimeWarp.Timed   (currentTime, runTimedIO)
import           Formatting               (build, sformat, (%))
import           Universum

import           Pos.Communication        (sendTx, serve)
import           Pos.Crypto               (hash, sign)
import           Pos.DHT                  (DHTNodeType (..), discoverPeers)
import           Pos.Slotting             (Timestamp (Timestamp))
import           Pos.Types                (Address, Coin, Tx (..), TxId, TxIn (..),
                                           TxOut (..), txF)
import           Pos.Worker               (runWorkers)
import           Pos.WorkMode             (NodeParams (..), WorkMode, getNodeContext,
                                           ncSecretKey, runRealMode)

-- | Get current time as Timestamp. It is intended to be used when you
-- launch the first node. It doesn't make sense in emulation mode.
getCurTimestamp :: IO Timestamp
getCurTimestamp = Timestamp <$> runTimedIO currentTime

-- | Run full node in any WorkMode.
runNode :: WorkMode m => NodeParams -> m ()
runNode NodeParams {..} = do
    peers <- discoverPeers DHTFull
    logInfo $ sformat ("Known peers: " % build) peers

    runWorkers
    serve (fromIntegral npPort)

-- | Run full node in real mode.
runNodeReal :: NodeParams -> IO ()
runNodeReal p = runRealMode p $ runNode p

-- | Construct Tx with a single input and single output and send it to
-- the given network addresses.
submitTx :: WorkMode m => [NetworkAddress] -> (TxId, Word32) -> (Address, Coin) -> m ()
submitTx na (txInHash, txInIndex) (txOutAddress, txOutValue) = do
    sk <- ncSecretKey <$> getNodeContext
    let txOuts = [TxOut {..}]
        txIns = [TxIn {txInSig = sign sk (txInHash, txInIndex, txOuts), ..}]
        tx = Tx {txInputs = txIns, txOutputs = txOuts}
        txId = hash tx
    logInfo $ sformat ("Submitting transaction: "%txF) tx
    logInfo $ sformat ("Transaction id: "%build) txId
    mapM_ (flip sendTx tx) na

-- | Submit tx in real mode.
submitTxReal :: NodeParams
             -> [NetworkAddress]
             -> (TxId, Word32)
             -> (Address, Coin)
             -> IO ()
submitTxReal p na inp = runRealMode p . submitTx na inp
