{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Grenade.Loss where

import           Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import GHC.TypeLits
import Numeric.LinearAlgebra.Data hiding ((===))
import qualified Numeric.LinearAlgebra.Static as NLA

import Grenade
import Test.Hedgehog.Hmatrix

genShapes :: Gen [S ('D1 10)]
genShapes = 
  let len = Range.linear 0 10
  in  Gen.list len (S1D <$> randomVectorNormalised)

prop_quadratic :: Property
prop_quadratic = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let costs  = map (uncurry quadratic) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> 0.5 * (sum $ zipWith (\a b -> (a - b) ^ 2) x y)
  let costs' = map f (zip xs' ys')
  costs === costs'
  
prop_quadratic' :: Property
prop_quadratic' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = quadratic'
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> zipWith (-) x y
  let costs' = map f (zip xs' ys')
  costs === costs'

prop_crossEntropy :: Property
prop_crossEntropy = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let costs  = map (uncurry crossEntropy) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> -1 * (sum $ zipWith (\a b -> b * (log a) + (1 - b) * (log (1 - a))) x y)
  let costs' = map f (zip xs' ys')
  costs === costs'

prop_crossEntropy' :: Property
prop_crossEntropy' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = crossEntropy'
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> zipWith (\a b -> (a - b) / ((1 - a) * a)) x y
  let costs' = map (\(u, v) -> f (u, v)) (zip xs' ys')
  costs === costs'

prop_exponential :: Property
prop_exponential = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let t  = 0.1
  let costs  = map (uncurry (exponential t)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> t * (exp (1/t * sum (zipWith (\a b -> (a - b) ^ 2) x y)))
  let costs' = map f (zip xs' ys')
  costs === costs'

prop_exponential' :: Property
prop_exponential' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let t = 0.1
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = exponential' t
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let g      = \(x, y, u) -> map ((*) (t * (exp (1/t * sum (zipWith (\a b -> (a - b) ^ 2) x y))))) u
  let f      = \(x, y) -> map ((*) (2 / t)) $ zipWith (-) x y
  let costs' = map (\(x, y) -> g(x, y, f (x, y))) (zip xs' ys')
  costs === costs'

prop_hellinger :: Property
prop_hellinger = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let costs  = map (uncurry hellinger) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> (1 / (sqrt 2)) * (sum $ zipWith (\a b -> (sqrt a - sqrt b) ^ 2) x y)
  let costs' = map f (zip xs' ys')
  costs === costs'

prop_hellinger' :: Property
prop_hellinger' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = hellinger'
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> zipWith (\a b -> ((sqrt a) - (sqrt b)) / ((sqrt 2) * (sqrt a))) x y
  let costs' = map (\(u, v) -> f (u, v)) (zip xs' ys')
  costs === costs'

prop_kullbackLeibler :: Property
prop_kullbackLeibler = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let costs  = map (uncurry kullbackLeibler) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> sum $ zipWith (\a b -> b * log (b / a)) x y
  let costs' = map f (zip xs' ys')
  costs === costs'

prop_kullbackLeibler' :: Property
prop_kullbackLeibler' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = kullbackLeibler'
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> zipWith (\a b -> -(b / a)) x y
  let costs' = map (\(u, v) -> f (u, v)) (zip xs' ys')
  costs === costs'

prop_genKullbackLeibler :: Property
prop_genKullbackLeibler = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let costs  = map (uncurry genKullbackLeibler) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> (sum $ zipWith (\a b -> b * log (b / a)) x y) - (sum y) + (sum x)
  let costs' = map f (zip xs' ys')
  costs === costs'


prop_genKullbackLeibler' :: Property
prop_genKullbackLeibler' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = genKullbackLeibler'
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> zipWith (\a b -> ((a - b) / a)) x y
  let costs' = map (\(u, v) -> f (u, v)) (zip xs' ys')
  costs === costs'


prop_itakuraSaito :: Property
prop_itakuraSaito = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let costs  = map (uncurry itakuraSaito) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> (sum $ zipWith (\a b -> (b/a) - (log (b/a)) - 1) x y)
  let costs' = map f (zip xs' ys')
  costs === costs'



prop_itakuraSaito' :: Property
prop_itakuraSaito' = property $ do
  xs <- forAll genShapes
  ys <- forAll genShapes
  let zs = zip xs ys
  let (LossFunction (l :: (S ('D1 10) -> S ('D1 10) -> S ('D1 10)))) = itakuraSaito'
  let costs  = map (extractVec . (uncurry l)) zs
  let xs'    = map extractVec xs
  let ys'    = map extractVec ys
  let f      = \(x, y) -> zipWith (\a b -> ((a - b) / (a * a))) x y
  let costs' = map (\(u, v) -> f (u, v)) (zip xs' ys')
  costs === costs'


tests :: IO Bool
tests = checkParallel $$(discover)
