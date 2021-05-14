module Test.DepTyCheck.Gen.Auto

import Data.Either
import Data.List1
import Data.So
import Data.Validated

import public Language.Reflection
import public Language.Reflection.Types
import public Language.Reflection.Syntax

import public Test.DepTyCheck.Gen

%default total
%language ElabReflection

--- Lists utilities ---

%inline
(.length) : List a -> Nat
xs.length = length xs

-- Not effective but clean
find' : (p : a -> Bool) -> (xs : List a) -> Maybe $ Fin xs.length
find' _ [] = Nothing
find' p (x::xs) = if p x then Just FZ else FS <$> find' p xs

--- Internal generation functions ---

generateGensFor' : (ty : TypeInfo) ->
                   (givenImplicitParams : List $ Fin ty.args.length) ->
                   (givenExplicitParams : List $ Fin ty.args.length) ->
                   (externalImplicitGens : List TypeInfo) -> -- todo maybe to use smth without constructors info instead of `TypeInfo`.
                   (externalHintedGens : List TypeInfo) ->
                   Elab ()

--- External generation interface and aux stuff for that ---

public export
data DatatypeArgPointer
       = Named Name
       | PositionalExplicit Nat

Show DatatypeArgPointer where
  show (Named x) = show x
  show (PositionalExplicit k) = "explicit #\{show k}"

public export
FromString DatatypeArgPointer where
  fromString = Named . fromString

namespace DatatypeArgPointer

  public export
  fromInteger : (x : Integer) -> (0 _ : So (x >= 0)) => DatatypeArgPointer
  fromInteger x = PositionalExplicit $ integerToNat x

Eq Namespace where
  (MkNS xs) == (MkNS ys) = xs == ys

Eq Name where -- I'm not sure that this implementation is correct for my case.
  (UN x)   == (UN y)   = x == y
  (MN x n) == (MN y m) = x == y && n == m
  (NS s n) == (NS p m) = s == p && n == m
  (DN x n) == (DN y m) = x == y && n == m
  (RF x)   == (RF y)   = x == y
  _ == _ = False

%inline
ResolvedArg : Type -> Type
ResolvedArg = ValidatedL DatatypeArgPointer

-- To report an error about particular argument.
toIndex : (ty : TypeInfo) -> DatatypeArgPointer -> ResolvedArg $ Fin ty.args.length
toIndex ty p@(Named n) = fromEitherL $ maybeToEither p $ find' ((== n) . name) ty.args
toIndex ty p@(PositionalExplicit k) = findNthExplicit ty.args k where
  findNthExplicit : (xs : List NamedArg) -> Nat -> ResolvedArg $ Fin xs.length
  findNthExplicit []                              _     = Invalid $ pure p
  findNthExplicit (MkArg _ ExplicitArg _ _ :: _ ) Z     = Valid FZ
  findNthExplicit (MkArg _ ExplicitArg _ _ :: xs) (S k) = FS <$> findNthExplicit xs k
  findNthExplicit (MkArg _ _           _ _ :: xs) n     = FS <$> findNthExplicit xs n

resolveGivens : (desc : String) -> {ty : TypeInfo} -> List DatatypeArgPointer -> Elab $ List $ Fin ty.args.length
resolveGivens desc givens = do
  let Valid resolved = traverse (toIndex ty) givens
    | Invalid badArgs => fail "Could not found arguments \{show badArgs} of type \{show ty.name} from the \{desc} givens"
  pure resolved

||| The entry-point function of automatic generation of `Gen`'s.
|||
||| Consider, you have a `data X (a : A) (b : B n) (c : C) where ...` and
||| you want an autogenerated `Gen` for `X`.
||| Say, you want to have `a` and `c` parameters of `X` to be set by the caller and the `b` parameter to be generated.
||| For this you can call `%runElab generateGensFor "X" [] ["a", "c"] [] []` and
||| you get (besides all) a function with a signature `(a : A) -> (c : C) -> (n ** b : B n ** X a b c)`.
|||
||| You can use positional arguments adderssing instead of named (espesially for unnamed arguments),
||| including mix of positional and named ones.
||| Arguments count from zero and only explicit arguments count.
||| I.e., the following call is equivalent to the one above: `%runElab generateGensFor "X" ["a", 2] [] []`.
|||
||| Say, you want `n` to be set by the caller to.
||| For this, you can use `%runElab generateGensFor "X" ["n"] ["a", "c"] [] []` and
||| the signature of the main generated function becomes `{n : _} -> (a : A) -> (c : C) -> (b : B n ** X a b c)`.
|||
||| Say, you want your generator to be parameterized with some external `Gen`'s.
||| Some of these `Gen`'s are known declared `%hint x : Gen Y`, some of them should go as an `auto` parameters.
||| Consider types `data Y where ...`, `data Z1 where ...` and `data Z2 (b : B n) where ...`.
||| If you want to use `%hint` for `Gen Y` and `Gen`'s for `Z1` and `Z2` to be `auto` parameters, you can use
||| `%runElab generateGensFor "X" ["n"] ["a", "c"] ["Z1", "Z2"] ["Y"]` to have a function with a signature
||| `Gen Z1 => ({n : _} -> {b : B n} -> Gen (Z2 b)) => {n : _} -> (a : A) -> (c : C) -> (b : B n ** X a b c)`.
||| `%hint _ : Gen Y` from the current scope will be used as soon as a value of type `Y` will be needed for generation.
export
generateGensFor : Name ->
                  (givenImplicitParams : List DatatypeArgPointer) ->
                  (givenExplicitParams : List DatatypeArgPointer) ->
                  (externalImplicitGens : List Name) ->
                  (externalHintedGens : List Name) ->
                  Elab ()
generateGensFor n defImpl defExpl extImpl extHint =
  generateGensFor'
    !(getInfo' n)
    !(resolveGivens "implicit" defImpl)
    !(resolveGivens "explicit" defExpl)
    !(for extImpl getInfo')
    !(for extHint getInfo')
