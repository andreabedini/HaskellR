-- |
-- Copyright: (C) 2013 Amgen, Inc.
module H.Prelude
  ( module Data.IORef
  , module Foreign
  , module H.HVal
  , module Language.R.Interpreter
  , liftR
  , symbol
  , string
  , strings
  , install
  , eval
  , evalPrint
  -- * constants
  , unboundValue
  , globalEnv
  , nilValue
  , missingArg
  ) where

import qualified Foreign.R as R
import qualified Language.R as LR

import Control.Monad ((<=<))
import System.IO.Unsafe ( unsafePerformIO )

-- Reexported modules.
import Data.IORef
import Data.Word
import Foreign hiding ( unsafePerformIO )
import H.HVal
import Language.R.Interpreter

liftR :: (R.SEXP a -> b) -> R.SomeSEXP -> b
liftR f (R.SomeSEXP x) = f (castPtr x)

symbol :: String -> R.SEXP R.Symbol
symbol = unsafePerformIO . LR.symbol

install :: String -> R.SEXP R.Symbol
install = unsafePerformIO . LR.install

string :: String -> R.SEXP (R.Vector Word8)
string = unsafePerformIO . LR.string

strings :: String -> R.SEXP (R.String)
strings = unsafePerformIO . LR.strings

eval :: R.SEXP a -> R.SEXP b
eval = unsafePerformIO . LR.eval

evalPrint :: R.SEXP a -> IO ()
evalPrint = R.printValue <=< LR.eval

unboundValue :: R.SEXP R.Symbol
unboundValue = unsafePerformIO $ readIORef LR.unboundValue

globalEnv :: R.SEXP R.Env
globalEnv = unsafePerformIO $ readIORef LR.globalEnv

nilValue :: R.SEXP R.Nil
nilValue = unsafePerformIO $ readIORef LR.nilValue

missingArg :: R.SEXP R.Symbol
missingArg = unsafePerformIO $ readIORef LR.missingArg
