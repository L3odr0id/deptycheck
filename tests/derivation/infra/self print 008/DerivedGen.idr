module DerivedGen

import AlternativeCore
import PrintDerivation

import Data.Vect

%default total

%language ElabReflection

%runElab printDerived {core=CallSelf} $ Fuel -> Gen MaybeEmpty (n : Nat ** a : Type ** Vect n a)
