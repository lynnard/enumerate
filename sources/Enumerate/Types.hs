{-# LANGUAGE RankNTypes, ScopedTypeVariables, DefaultSignatures, TypeOperators #-}
{-# LANGUAGE FlexibleInstances, FlexibleContexts, LambdaCase #-}
{-# LANGUAGE TypeFamilies, ExplicitNamespaces, DataKinds, UndecidableInstances #-}

{-# LANGUAGE DeriveGeneric, DeriveDataTypeable #-}

{- | enumerate all values in a finite type.

e.g.

@
data A
  = A0 Bool
  | A1 (Either Bool) (Maybe Bool)
  | A2 (Bool, Bool)
  | A3 (Set Bool)
  deriving (Show,Generic,Enumerable)

> enumerate
A0 False
A0 True
A1 ...

> cardinality ([]::[A])

@

see the 'Enumerable' class for documentation.

see "Enumerate.Example" for examples.

can also help automatically derive @<https://hackage.haskell.org/package/QuickCheck/docs/Test-QuickCheck-Arbitrary.html QuickCheck>@ instances:

@
newtype ValidString = ValidString String
 deriving (Show)
validStrings :: [String]
makeValidString :: String -> Maybe ValidString
makeValidString s = if s `member` validStrings then Just (ValidString s) else Nothing
instance 'Enumerable' ValidString where enumerated = ValidString \<$> validStrings ... -- manually (since normal String's are infinite)
instance <https://hackage.haskell.org/package/QuickCheck/docs/Test-QuickCheck.html#t:Arbitrary Arbitrary> ValidString where arbitrary = elements 'enumerated'

data ValidName = ValidName ValidString ValidString | CoolValidName [ValidString]
 deriving (Show,Generic)
instance 'Enumerable' ValidName -- automatically

instance Arbitrary ValidName where arbitrary = elements 'enumerated'
@

Provides instances for all base types (whenever possible):

* under @Data.@ \/ @Control.@ \/ @System.@ \/ @Text.@, and even @GHC.@
* even non-'Enum's
* except when too large (like 'Int') (see "Enumerate.Large")

background on @Generics@:

* <https://hackage.haskell.org/package/base-4.8.1.0/docs/GHC-Generics.html GHC.Generics>

also provides instances for:

* sets

* vinyl records

related packages:

* <http://hackage.haskell.org/package/enumerable enumerable>.
no @Generic@ instance.

* <http://hackage.haskell.org/package/universe universe>
no @Generic@ instance.

* <http://hackage.haskell.org/package/prelude-safeenum-0.1.1.2/docs/Prelude-SafeEnum.html SafeEnum>
only @Enum@s

* <http://hackage.haskell.org/package/emgm-0.4/docs/Generics-EMGM-Functions-Enum.html emgm>.
  allows infinite lists (by convention). too heavyweight.

* <https://hackage.haskell.org/package/testing-feat-0.4.0.2/docs/Test-Feat-Class.html#t:Enumerable testing-feat>.
too heavyweight (testing framework).

* <https://hackage.haskell.org/package/smallcheck smallcheck>
too heavyweight (testing framework). Series enumerates up to some depth and can enumerated infinitely-inhabited types.

* <https://hackage.haskell.org/package/quickcheck quickcheck>
too heavyweight (testing framework, randomness unnecessary).

-}

module Enumerate.Types where
import Enumerate.Extra

import Data.Vinyl (Rec(..))
import Control.DeepSeq (force)

import qualified Data.Set as Set
import           GHC.Generics
import System.Timeout (timeout)
import Data.Ix (Ix(..))
-- import GHC.TypeLits (Nat, KnownNat, natVal, type (+), type (*), type (^))

import           Data.Void (Void)
import           Data.Word (Word8, Word16)
import           Data.Int (Int8, Int16)
import Prelude (Enum(..))

-- for instances...
import Data.Typeable ((:~:)(..))
import Control.Applicative (Const(..))
import Data.Functor.Identity (Identity(..))
import Data.Type.Coercion (Coercion(..))
import Data.Coerce (Coercible)
import Data.Char (GeneralCategory)
-- import Data.Ratio (Ratio,(%)) -- from Prelude.Spiros
import Data.Complex (Complex(..))
--
import Control.Exception (ArithException(..),AsyncException(..),NonTermination(..),NestedAtomically(..),BlockedIndefinitelyOnMVar(..),BlockedIndefinitelyOnSTM(..),AllocationLimitExceeded(..),Deadlock(..))
import Data.Monoid (Any,All,Dual,First,Last,Sum,Product,Alt,Endo)
import System.IO (IOMode,SeekMode,Newline(..),NewlineMode(NewlineMode))
import Text.Printf (FormatAdjustment(..),FormatSign(..))
import Foreign.C (CChar,CWchar,CSChar,CUChar,CShort,CUShort)
import System.Posix.Types (CIno,CMode)
import GHC.Exts(Down(..),SpecConstrAnnotation(..))
--
-- TODO CCc
-- import GHC.Conc.Windows (ConsoleEvent) -- platform-specific module
import GHC.IO.Buffer (BufferState(..))
import GHC.IO.Device (IODeviceType(..))
import GHC.IO.Encoding.Failure (CodingFailureMode(..))
import GHC.IO.Encoding.Types (CodingProgress(..))
import GHC.RTS.Flags (DoTrace,DoHeapProfile,DoCostCentres,GiveGCStats)

--import Data.Modular (not on stack)
-- * modular integers


{-$setup

>>> import Prelude

-}

{- | enumerate the set of all values in a (finitely enumerable) type.
enumerates depth first.

generalizes 'Enum's to any finite/discrete type. an Enumerable is either:

* an Enum
* a product of Enumerables
* a sum of Enumerables

can be implemented automatically via its 'Generic' instance.

laws:

* finite:

    * @'cardinality' /= _|_@

* consistent:

    * @'cardinality' _ = 'length' 'enumerated'@

    so you can index the 'enumerated' with a nonnegative index below the 'cardinality'.

* distinct:

    * @(Eq a) => 'nub' 'enumerated' == 'enumerated'@

* complete:

    * @x `'elem'` 'enumerated'@

* coincides with @Bounded@ @Enum@s:

    * @('Enum' a, 'Bounded' a) => 'enumerated' == 'boundedEnumerated'@

    * @('Enum' a) => 'enumerated' == 'enumEnumerated'@

(@Bounded@ constraint elided for convenience, but relevant.)

("inputs" a type, outputs a list of values).

Every type in `base` (that can be an instance) is an instance.

-}
class Enumerable a where

 enumerated :: [a]

 default enumerated :: (Generic a, GEnumerable (Rep a)) => [a]
 enumerated = to <$> genumerated

 cardinality :: proxy a -> Natural
 cardinality _ = genericLength (enumerated :: [a])
 -- overrideable for performance, but don't lie!

 -- default cardinality :: (Generic a, GEnumerable (Rep a)) => proxy a -> Natural
 -- cardinality _ = gcardinality (Proxy :: Proxy (Rep a))
 -- TODO merge both methods into one that returns their pair

{-
instance Enumerable where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality

instance Enumerable where
 enumerated = []

instance (Enumerable a) => Enumerable (X a) where
   enumerated = X <$> enumerated

-}

{-| wrap any @(Bounded a, Enum a)@ to be a @Enumerable@ via 'boundedEnumerated'.

(avoids @OverlappingInstances@).

-}
newtype WrappedBoundedEnum a = WrappedBoundedEnum { unwrapBoundedEnum :: a }

--------------------------------------------------------------------------------
 -- main base types

{- NOTE: to declare instances:

* use default, when Generic (easiest)
* use boundedEnumerated/boundedCardinality, when only Bounded (faster and safer than enumEnumerated)
* use enumEnumerated, when only Enum (doesn't import constructors, only type)
* use constructors, when no relevant instances

-}

--NOTE this file takes ~1s to build. split into another with orphans?

instance Enumerable Void
instance Enumerable ()
instance Enumerable Bool
instance Enumerable Ordering

-- | (phantom in @a@)
instance Enumerable (Proxy a)

instance (Enumerable a) => Enumerable (Identity a) where
  enumerated = Identity <$> enumerated

instance (Enumerable a) => Enumerable (Const a b) where
  enumerated = Const <$> enumerated

instance (a ~ b) => Enumerable (a :~: b) where
  enumerated = [Refl]

instance (Coercible a b) => Enumerable (Coercion a b) where
  enumerated = [Coercion]

-- Enumerable TypeRep -- we can't list all known types, statically (because separate compilation).
-- but dynamically, maybe? and probably constant throughout the running program i.e. still pure.

{- |

@-- ('toInteger' prevents overflow)@

>>> 1 + toInteger (maxBound::Int8) - toInteger (minBound::Int8)
256

-}
instance Enumerable Int8  where
  -- type Cardinality Int8 = 256 -- 2^8
  enumerated = boundedEnumerated
  cardinality = boundedCardinality

instance Enumerable Word8 where
  -- type Cardinality Word8 = 256 -- 2^8
  enumerated = boundedEnumerated
  cardinality = boundedCardinality

{- |

>>> 1 + toInteger (maxBound::Int16) - toInteger (minBound::Int16)
65536

-}
instance Enumerable Int16  where
   -- type Cardinality Int16 = 65536 -- 2^16
   enumerated = boundedEnumerated
   cardinality = boundedCardinality

instance Enumerable Word16 where
  -- type Cardinality Word16 = 65536 -- 2^16
  enumerated = boundedEnumerated
  cardinality = boundedCardinality

{- | there are only a million (1,114,112) characters.

>>> import Data.Char (ord,chr)  -- 'ord', 'chr'

>>> ord minBound
0

>>> ord maxBound
1114111

>>> length [chr 0 ..]
1114112

-}
instance Enumerable Char where
  -- type Cardinality Char = 1114112
  enumerated = boundedEnumerated
  cardinality = boundedCardinality

{-| the sum type.

the 'cardinality' is the sum of the cardinalities of @a@ and @b@.

>>> cardinality ([] :: [Either Bool Ordering])
5

-}
instance (Enumerable a, Enumerable b) => Enumerable (Either a b) where
 -- type Cardinality (Either a b) = (Cardinality a) + (Cardinality b)
 enumerated    = (Left <$> enumerated) ++ (Right <$> enumerated)
 cardinality _ = cardinality (Proxy :: Proxy a) + cardinality (Proxy :: Proxy b)

{-| -}
instance (Enumerable a) => Enumerable (Maybe a) where
 -- type Cardinality (Maybe a) = 1 + (Cardinality a)
 enumerated    = Nothing : (Just <$> enumerated)
 cardinality _ = 1 + cardinality (Proxy :: Proxy a)

{-| the product type.

the 'cardinality' is the product of the cardinalities of @a@ and @b@.

>>> cardinality ([] :: [(Bool,Ordering)])
6

-}
instance (Enumerable a, Enumerable b) => Enumerable (a, b) --where
 -- enumerated    = (,) <$> enumerated <*> enumerated
 -- cardinality _ = cardinality (Proxy :: Proxy a) * cardinality (Proxy :: Proxy b)

-- | 3
instance (Enumerable a, Enumerable b, Enumerable c) => Enumerable (a, b, c)
-- | 4
instance (Enumerable a, Enumerable b, Enumerable c, Enumerable d) => Enumerable (a, b, c, d)
-- | 5
instance (Enumerable a, Enumerable b, Enumerable c, Enumerable d, Enumerable e) => Enumerable (a, b, c, d, e)
-- | 6
instance (Enumerable a, Enumerable b, Enumerable c, Enumerable d, Enumerable e, Enumerable f) => Enumerable (a, b, c, d, e, f)
-- | 7
instance (Enumerable a, Enumerable b, Enumerable c, Enumerable d, Enumerable e, Enumerable f, Enumerable g) => Enumerable (a, b, c, d, e, f, g)

-- instance (Enumerable a, Enumerable b, Enumerable c, Enumerable d, Enumerable e, Enumerable f, Enumerable g, Enumerable h) => Enumerable (a, b, c, d, e, f, g, h)
{-
Could not deduce (Generic (a, b, c, d, e, f, g, h))
     arising from a use of `Enumerate.Types.$gdmenumerated'
-}

{-|

the 'cardinality' is the cardinality of the 'powerSet' of @a@, i.e. @2^|a|@.
warning: it grows quickly. don't try to take the power set of 'Char'! or even 'Word8'.

the 'cardinality' call is efficient (depending on the efficiency of the base type's call).
you should be able to safely call 'enumerateBelow', unless the arithmetic itself becomes too large.

>>> enumerated :: [Set Bool]
[fromList [],fromList [False],fromList [False,True],fromList [True]]

-}
instance (Enumerable a, Ord a) => Enumerable (Set a) where
 -- type Cardinality (Set a) = 2 ^ (Cardinality a)
 enumerated    = (Set.toList . powerSet . Set.fromList) enumerated
 cardinality _ = 2 ^ cardinality (Proxy :: Proxy a)

--------------------------------------------------------------------------------
-- more base types

instance Enumerable GeneralCategory where
  enumerated = boundedEnumerated
  cardinality = boundedCardinality

instance Enumerable IOMode where
  enumerated = enumEnumerated
  -- enumerated = [ReadMode,WriteMode,AppendMode,ReadWriteMode]
 -- enumerated = boundedEnumerated
 -- cardinality = boundedCardinality

instance Enumerable SeekMode where
  enumerated = enumEnumerated
  -- enumerated = [AbsoluteSeek,RelativeSeek,SeekFromEnd]
 -- enumerated = boundedEnumerated
 -- cardinality = boundedCardinality

instance Enumerable ArithException where
  enumerated =
   [ Overflow
   , Underflow
   , LossOfPrecision
   , DivideByZero
   , Denormal
   , RatioZeroDenominator
   ]

instance Enumerable AsyncException where
 enumerated = [StackOverflow, HeapOverflow, ThreadKilled, UserInterrupt]

instance Enumerable NonTermination where
 enumerated = [NonTermination]

instance Enumerable NestedAtomically where
 enumerated = [NestedAtomically]

instance Enumerable BlockedIndefinitelyOnMVar where
 enumerated = [BlockedIndefinitelyOnMVar]

instance Enumerable BlockedIndefinitelyOnSTM where
 enumerated = [BlockedIndefinitelyOnSTM]

instance Enumerable AllocationLimitExceeded where
 enumerated = [AllocationLimitExceeded]

instance Enumerable Deadlock where
 enumerated = [Deadlock]

instance Enumerable Newline where
 enumerated = [LF,CRLF]

instance Enumerable NewlineMode where
 enumerated = NewlineMode <$> enumerated <*> enumerated

instance Enumerable FormatAdjustment where
 enumerated = [LeftAdjust,ZeroPad]

instance Enumerable FormatSign where
 enumerated = [SignPlus,SignSpace]

-- instance Enumerable CCc where
--   enumerated = boundedEnumerated
--   cardinality = boundedCardinality

instance Enumerable All
instance Enumerable Any
instance (Enumerable a) => Enumerable (Dual a)
instance (Enumerable a) => Enumerable (First a)
instance (Enumerable a) => Enumerable (Last a)
instance (Enumerable a) => Enumerable (Sum a)
instance (Enumerable a) => Enumerable (Product a)
instance (Enumerable (a -> a)) => Enumerable (Endo a)
instance (Enumerable (f a)) => Enumerable (Alt f a)

instance (Enumerable a) => Enumerable (Complex a) where
  enumerated = (:+) <$> enumerated <*> enumerated

{-| (@a@ can be any @Enumerable@,
unlike the @Enum@ instance where @a@ is an @Integral@).
-}
-- instance (Enumerable a) => Enumerable (Ratio a) where
--   enumerated = (%) <$> enumerated <*> enumerated

--------------------------------------------------------------------------------
-- ghc-only

instance (Enumerable a) => Enumerable (Down a) where
   enumerated = Down <$> enumerated

instance Enumerable CIno where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CMode where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CChar where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CWchar where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CSChar where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CUChar where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CShort where
 enumerated = boundedEnumerated
 cardinality = boundedCardinality
instance Enumerable CUShort where
  enumerated = boundedEnumerated
  cardinality = boundedCardinality

instance Enumerable Associativity
  -- LeftAssociative,RightAssociative,NotAssociative

instance Enumerable SpecConstrAnnotation where
 enumerated = [NoSpecConstr,ForceSpecConstr]

-- instance Enumerable ConsoleEvent where
--  enumerated = enumEnumerated

instance Enumerable BufferState where
 enumerated = [ReadBuffer,WriteBuffer]

instance Enumerable IODeviceType where
  enumerated = [Directory,Stream,RegularFile,RawDevice]

instance Enumerable CodingFailureMode where
 enumerated = [ErrorOnCodingFailure,IgnoreCodingFailure,TransliterateCodingFailure,RoundtripFailure]

instance Enumerable CodingProgress where
  enumerated = [InputUnderflow,OutputUnderflow,InvalidSequence]

instance Enumerable DoTrace where
  enumerated = enumEnumerated
instance Enumerable DoHeapProfile where
  enumerated = enumEnumerated
instance Enumerable DoCostCentres where
  enumerated = enumEnumerated
instance Enumerable GiveGCStats where
  enumerated = enumEnumerated

{- TODO why not generic/enum/bounded? ghc build time? to avoid recursive imports?

nothing:
ArithException
AsyncException
NonTermination
NestedAtomically
BlockedIndefinitelyOnMVar
BlockedIndefinitelyOnSTM
AllocationLimitExceeded
Deadlock
Fixity
FormatAdjustment
FormatSign
Newline
CCc
CChar
CWChar
CSChar
CUChar
CShort
CUShort

no generic:
NewlineMode
Ratio

no bounded:
IOMode
SeekMode
ConsoleEvent
DoTrace
DoHeapProfile
DoCostCentres
GiveGCStats

-}

--------------------------------------------------------------------------------
-- package types

instance (Bounded a, Enum a) => Enumerable (WrappedBoundedEnum a) where
 -- type Cardinality (WrappedBoundedEnum a) = Cardinality a
 enumerated    = WrappedBoundedEnum <$> boundedEnumerated
 cardinality _ = boundedCardinality (Proxy :: Proxy a)

--------------------------------------------------------------------------------
-- dependency types

{-| the cardinality is a product of cardinalities. -}
instance (Enumerable (f a), Enumerable (Rec f as)) => Enumerable (Rec f (a ': as)) where
 -- type Cardinality (Rec f (a ': as)) = (Cardinality (f a)) * (Cardinality (Rec f as))
 enumerated =  (:&) <$> enumerated <*> enumerated
 cardinality _ = cardinality (Proxy :: Proxy (f a)) * cardinality (Proxy :: Proxy (Rec f as))

{-|  -}
instance Enumerable (Rec f '[]) where
 -- type Cardinality (Rec f '[]) = 1
 enumerated = [RNil]
 cardinality _ = 1

{-
-- | (from the @modular-arithmetic@ package)
instance (Integral i, Num i, KnownNat n) => Enumerable (Mod i n) where
 -- type Cardinality (Mod i n) = n
 enumerated    = toMod <$> [0 .. fromInteger (natVal (Proxy :: Proxy n) - 1)]
 cardinality _ = fromInteger (natVal (Proxy :: Proxy n))
-}

--------------------------------------------------------------------------------

-- | "Generic Enumerable", lifted to unary type constructors.
class GEnumerable f where
-- class (KnownNat (GCardinality f)) => GEnumerable f where
 -- type GCardinality f :: Nat
 genumerated :: [f x]
 gcardinality :: proxy f -> Natural

-- | empty list
instance GEnumerable (V1) where
 -- type GCardinality (V1) = 0
 genumerated    = []
 gcardinality _ = 0
 {-# INLINE gcardinality #-}

-- | singleton list
instance GEnumerable (U1) where
 -- type GCardinality (U1) = 1
 genumerated    = [U1]
 gcardinality _ = 1
 {-# INLINE gcardinality #-}

{-| call 'enumerated'

-}
instance (Enumerable a) => GEnumerable (K1 R a) where
 -- type GCardinality (K1 R a) = Cardinality a
 genumerated    = K1 <$> enumerated
 gcardinality _ = cardinality (Proxy :: Proxy a)
 {-# INLINE gcardinality #-}

-- | multiply lists with @concatMap@
instance (GEnumerable (f), GEnumerable (g)) => GEnumerable (f :*: g) where
 -- type GCardinality (f :*: g) = (GCardinality f) * (GCardinality g)
 genumerated    = (:*:) <$> genumerated <*> genumerated
 gcardinality _ = gcardinality (Proxy :: Proxy (f)) * gcardinality (Proxy :: Proxy (g))
 {-# INLINE gcardinality #-}

-- | add lists with @(<>)@
instance (GEnumerable (f), GEnumerable (g)) => GEnumerable (f :+: g) where
 -- type GCardinality (f :+: g) = (GCardinality f) + (GCardinality g)
 genumerated    = map L1 genumerated ++ map R1 genumerated
 gcardinality _ = gcardinality (Proxy :: Proxy (f)) + gcardinality (Proxy :: Proxy (g))
 {-# INLINE gcardinality #-}

-- | ignore selector metadata
instance (GEnumerable (f)) => GEnumerable (M1 S t f) where
 -- type GCardinality (M1 S t f) = GCardinality f
 genumerated    = M1 <$> genumerated
 gcardinality _ = gcardinality (Proxy :: Proxy (f))
 {-# INLINE gcardinality #-}

-- | ignore constructor metadata
instance (GEnumerable (f)) => GEnumerable (M1 C t f) where
 -- type GCardinality (M1 C t f) = GCardinality f
 genumerated    = M1 <$> genumerated
 gcardinality _ = gcardinality (Proxy :: Proxy (f))
 {-# INLINE gcardinality #-}

-- | ignore datatype metadata
instance (GEnumerable (f)) => GEnumerable (M1 D t f) where
 -- type GCardinality (M1 D t f) = GCardinality f
 genumerated    = M1 <$> genumerated
 gcardinality _ = gcardinality (Proxy :: Proxy (f))
 {-# INLINE gcardinality #-}

--------------------------------------------------------------------------------

{- | for non-'Generic' Bounded Enums:

@
instance Enumerable _ where
 'enumerated' = boundedEnumerated
 'cardinality' = 'boundedCardinality'
@

-}
boundedEnumerated :: (Bounded a, Enum a) => [a]
boundedEnumerated = enumFromTo minBound maxBound

{-| for non-'Generic' Bounded Enums.

Assuming 'Bounded' is correct, safely stop the enumeration
(and know where to start).

behavior may be undefined when the cardinality of @a@ is larger than
the cardinality of @Int@. this should be okay, as @Int@ is at least as big as
@Int64@, which is at least as big as all the monomorphic types in @base@ that
instantiate @Bounded@. you can double-check with:

>>> boundedCardinality (const(undefined::Int))   -- platform specific
18446744073709551616

@
-- i.e. 1 + 9223372036854775807 - (-9223372036854775808)
@

works with non-zero-based Enum instances, like @Int64@ or a custom
@toEnum/fromEnum@. assumes the enumeration's numbering is
contiguous, e.g. if @fromEnum 0@ and @fromEnum 2@
both exist, then @fromEnum 1@ should exist too.

-}
boundedCardinality :: forall proxy a. (Bounded a, Enum a) => proxy a -> Natural
boundedCardinality _ = fromInteger (1 + (toInteger (fromEnum (maxBound::a))) - (toInteger (fromEnum (minBound::a))))

{- | for non-'Generic' Enums:

@
instance Enumerable ... where
 'enumerated' = enumEnumerated
@

the enum should still be bounded.

-}
enumEnumerated :: (Enum a) => [a]
enumEnumerated = enumFrom (toEnum 0)

{- | for non-'Generic' Bounded Indexed ('Ix') types:

@
instance Enumerable _ where
 'enumerated' = indexedEnumerated
 'cardinality' = 'indexedCardinality'
@

-}
indexedEnumerated :: (Bounded a, Ix a) => [a]
indexedEnumerated = range (minBound,maxBound)

{- | for non-'Generic' Bounded Indexed ('Ix') types.
-}
indexedCardinality :: forall proxy a. (Bounded a, Ix a) => proxy a -> Natural
indexedCardinality _ = int2natural (rangeSize (minBound,maxBound::a))

{-| enumerate only when the cardinality is small enough.
returns the cardinality when too large.

>>> enumerateBelow 2 :: Either Natural [Bool]
Left 2

>>> enumerateBelow 100 :: Either Natural [Bool]
Right [False,True]

useful when you've established that traversing a list below some length
and consuming its values is reasonable for your application.
e.g. after benchmarking, you think you can process a billion entries within a minute.

-}
enumerateBelow :: forall a. (Enumerable a) => Natural -> Either Natural [a] --TODO move
enumerateBelow maxSize = if theSize `lessThan` maxSize
  then Right enumerated
  else Left theSize
 where
 theSize = cardinality (Proxy :: Proxy a)

{-| enumerate only when completely evaluating the list doesn't timeout
(before the given number of microseconds).

>>> enumerateTimeout (2 * 10^6) :: IO (Maybe [Bool])  -- two seconds
Just [False,True]

-}
enumerateTimeout :: (Enumerable a, NFData a) => Int -> IO (Maybe [a]) --TODO move
enumerateTimeout maxDuration
 = timeout maxDuration (return$ force enumerated)
