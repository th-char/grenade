{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

import           Control.Applicative
import           Control.DeepSeq
import           Control.Monad
import           Control.Monad.Random
import           Control.Monad.Trans.Except

import           Data.Serialize
import qualified Data.ByteString              as B
import qualified Data.Attoparsec.Text         as A
import           Data.List                    (foldl', maximumBy)
import qualified Data.Text                    as T
import qualified Data.Text.IO                 as T
import qualified Data.Vector.Storable         as V
import           Data.Ord
import           Data.Maybe                   (fromMaybe)
import           Data.Word
import           Data.Bits
import           Data.Convertible

import           Debug.Trace

import           Numeric.LinearAlgebra.Data   (toLists, cmap, flatten)
import           Numeric.LinearAlgebra        (maxIndex)
import qualified Numeric.LinearAlgebra.Static as SA
import qualified Numeric.LinearAlgebra.Devel  as U

import           Graphics.Gloss
import qualified Graphics.Gloss.Interface.IO.Interact as GI

import           Options.Applicative

import           Unsafe.Coerce 

import           Grenade
import           Grenade.Utils.OneHot
import           Grenade.Layers.Internal.Shrink

type MNIST
  = Network
    '[ Convolution 1 10 5 5 1 1, Pooling 2 2 2 2, Relu
     , Convolution 10 16 5 5 1 1, Pooling 2 2 2 2, Reshape, Relu
     , FullyConnected 256 80, Logit, FullyConnected 80 10, Logit]
    '[ 'D2 28 28, 'D3 24 24 10, 'D3 12 12 10, 'D3 12 12 10
     , 'D3 8 8 16, 'D3 4 4 16, 'D1 256, 'D1 256
     , 'D1 80, 'D1 80, 'D1 10, 'D1 10]

data MNistLoadOpts = MNistLoadOpts FilePath -- Model path

mnist' :: Parser MNistLoadOpts
mnist' = MNistLoadOpts <$> argument str  (metavar "MODEL")

netLoad :: FilePath -> IO MNIST
netLoad modelPath = do
  modelData <- B.readFile modelPath
  either fail return $ runGet (get :: Get MNIST) modelData

runNet' :: MNIST -> S ('D2 28 28) -> String
runNet' net m = (\(S1D ps) -> let (p, i) = (getProb . V.toList) (SA.extract ps)
                              in "This number is " ++ show i ++ " with probability " ++ show (p * 100) ++ "%") $ runNet net m
  where
    getProb :: (Show a, Ord a) => [a] -> (a, Int)
    getProb xs = maximumBy (comparing fst) (zip xs [0..])

showShape' :: S ('D2 a b) -> String
showShape' (S2D mm) = 
  let m  = SA.extract mm
      ms = toLists m
      render n' | n' <= 0.2 * 255  = ' '
                | n' <= 0.4 * 255  = '.'
                | n' <= 0.6 * 255  = '-'
                | n' <= 0.8 * 255  = '='
                | otherwise =  '#'
      px = (fmap . fmap) render ms
  in unlines px

data MouseState = MouseDown | MouseUp
data Canvas = Canvas (S ('D2 224 224)) MouseState MNIST

renderCanvas :: Canvas -> Picture
renderCanvas (Canvas (S2D !arr) _ _)
    = bitmapOfForeignPtr 224 224 (BitmapFormat BottomToTop PxABGR) (unsafeCoerce ptr) False
  where 
    convColor :: Double -> Word32
    convColor p = let p'  =  convert p :: Word32
                      !w  =  unsafeShiftL p' 24
                         .|. unsafeShiftL p' 16
                         .|. unsafeShiftL p' 8
                         .|. 255
                  in w

    m'          = flatten $ SA.extract $ arr
    m''         = U.mapVectorWithIndex (const convColor) m'
    (ptr, _, _) = U.unsafeToForeignPtr m''

handleInput :: GI.Event -> Canvas -> Canvas
handleInput e@(GI.EventKey (GI.MouseButton GI.LeftButton) ks _ _) (Canvas arr'@(S2D !arr) mb net) = 
  case ks of
    GI.Down -> Canvas arr' MouseDown net
    GI.Up   -> trace (runNet' net shrunk) $ Canvas arr' MouseUp net
  where 
    shrunk :: S ('D2 28 28)
    shrunk = S2D $ fromMaybe (error "") $ SA.create $ shrink_2d 224 224 28 28 (SA.extract arr)

handleInput e@(GI.EventKey (GI.Char 'c') ks _ _) (Canvas arr'@(S2D !arr) mb net) = 
  case ks of
    GI.Down -> Canvas arr'   mb net
    GI.Up   -> Canvas arrNew mb net
  where 
    arrNew = S2D $ fromMaybe (error "") $ SA.create clean
    clean  = U.mapMatrixWithIndex (const (const 255)) (SA.extract arr)

handleInput e@(GI.EventMotion (y, x)) cvs@(Canvas arr mb net) = case mb of 
  MouseDown -> Canvas (draw arr (convert x + 112) (convert y + 112)) mb net
  MouseUp   -> cvs

handleInput _ c = c

draw :: S ('D2 224 224) -> Int -> Int -> S ('D2 224 224)
draw (S2D arr) x y = S2D $ fromMaybe (error "") $ SA.create m
  where 
    m = U.mapMatrixWithIndex f (SA.extract arr)

    f (x', y') p = if (x - x') ^ 2 + (y - y') ^ 2 <= 50 then 0 else p

main :: IO ()
main = do 
    MNistLoadOpts modelPath <- execParser (info (mnist' <**> helper) idm)
    
    net <- netLoad modelPath
    putStrLn "Successfully loaded model"
  
    let initialCanvas = Canvas initialMat MouseUp net

    play window backgroundColor 30 initialCanvas renderCanvas handleInput (const id)
  where
    window          = InWindow "Draw here!" (224, 224) (100, 100)
    backgroundColor = makeColor 255 255 255 0
    initialMat      = fromMaybe (error "") $ fromStorable . V.fromList $ replicate (224 * 224) 255