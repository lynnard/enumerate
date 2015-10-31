{-| see "Data.Enumerable.Types" for detailed documentation. 

to import every symbol in this package, run this in GHCi:

@
:m +  Data.Enumerate  Data.Enumerate.Extra  Data.Enumerate.Large  Data.Enumerate.Function 
@

the modules "Data.Enumerate.Large" and "Data.Enumerate.Function" have orphan instances for large types, 
and aren't reexported by default. 
this makes attempting to enumerate them a type error, rather than runtime non-termination. 

-}
module Data.Enumerate
 ( module Data.Enumerate.Types
 , module Data.Enumerate.Reify
 -- , module Data.Enumerate.Domain 
 , module Data.Enumerate.Map 
 ) where 
import Data.Enumerate.Types
import Data.Enumerate.Reify
-- import Data.Enumerate.Domain
import Data.Enumerate.Map
