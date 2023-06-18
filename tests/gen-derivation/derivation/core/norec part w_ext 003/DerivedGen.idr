module DerivedGen

import RunDerivedGen

%default total

%language ElabReflection

data X = MkX (String, Nat, String)

%runElab derive "X" [Generic, Meta, Show]

export
checkedGen : Fuel -> (Fuel -> Gen MaybeEmpty String) => (Fuel -> Gen MaybeEmpty Nat) => Gen MaybeEmpty X
checkedGen = deriveGen

main : IO ()
main = runGs [ G $ \fl => checkedGen fl @{smallStrs} @{smallNats} ]
