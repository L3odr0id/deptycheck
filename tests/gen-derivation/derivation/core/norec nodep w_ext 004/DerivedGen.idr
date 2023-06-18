module DerivedGen

import RunDerivedGen

%default total

%language ElabReflection

data X = X1 String Nat | X2 Nat | X3 String

%runElab derive "X" [Generic, Meta, Show]

export
checkedGen : Fuel -> (Fuel -> Gen MaybeEmpty String) => (Fuel -> Gen MaybeEmpty Nat) => Gen MaybeEmpty X
checkedGen = deriveGen

main : IO ()
main = runGs [ G $ \fl => checkedGen fl @{smallStrs} @{smallNats} ]
