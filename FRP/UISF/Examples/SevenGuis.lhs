
Last modified by: Daniel Winograd-Cort
Last modified on: 8/13/2014

This module is intended to show UISF's ability to implement the 
seven GUIs listed on https://github.com/eugenkiss/7guis/wiki.

We begin my including the language pragma for arrows, as they are 
integral for easily writing arrowized FRP.

> {-# LANGUAGE Arrows #-}

We declare the module name and import UISF

> module FRP.UISF.Examples.SevenGuis where
> import FRP.UISF
> import Text.Read (readMaybe)  -- For Temperature Converter
> import Control.Monad (join)   -- For Temperature Converter
> 
> import System.Locale      -- For Flight Booker
> import Data.Time          -- For Flight Booker
> import Data.Time.Clock (getCurrentTime)   -- For Flight Booker
> import Data.Time.Format   -- For Flight Booker
> import Data.Maybe (isJust)
> 
> import FRP.UISF.Widget (block, padding) -- For Timer
> 
> import Data.List (isInfixOf)  -- For CRUD
> import Data.Char (toLower)    -- For CRUD


---------------------------------------
--------------- Counter ---------------
---------------------------------------

The first GUI is a simple counter consisting of a button and a 
displayed field indicating how many times the button as been pressed.

We'll start by creating the UISF.  Note that rightLeft is used here 
to set the layout ordering.

The button widget returns a stream of True or False depending on whether 
the button is down or not, so we use the "edge" transformer to turn that 
stream into an event stream, with unit events every time the button is 
pressed and nothing otherwise.

Arrows make it easy to send data from one widget to another.  In this case, 
we use the rec keyword and the delay operator to create some state in our 
GUI (to keep track of the count), and then feedback the v value upon itself, 
updating as necessary when the button is pressed.

> counterSF :: UISF () ()
> counterSF = rightLeft $ proc _ -> do
>   b <- edge <<< button "Count" -< ()
>   rec v <- delay 0 -< maybe v (const $ v+1) b
>   display -< v

This is the guts of the counter, and to run it, we merely need 
to pass it to runUI.

> counter :: IO ()
> counter = runUI (250,24) "Counter" counterSF


---------------------------------------
-------- Temperature Converter --------
---------------------------------------

The second GUI is a temperature converter that dynamically converts 
between celsius and fahrenheit.  This introduces text parsing and 
bidirectional dataflow, the first of which is fairly easy with 
standard Haskell, and the second of which is simple with arrowized 
FRP.

The textboxE function takes a starting String to create a widget that 
accepts an Event String as input and produces String as output.  We use 
the "unique" transformer to transform this output into events that only 
update when a change occurs.

The first half of the program sets up the 4 widgets (two textboxes and 
two labels), and the second half does the text parsing and actual 
conversion (note that this half is all pure Haskell code).

Note that because we are moving data bidirectionally, we have actually 
coded a recursive structure where each field defines the other.  In order 
to prevent infinite recursion, we must put a "delay" into the loop, and 
so we do this twice, once for each textbox.

> tempCovertSF :: UISF () ()
> tempCovertSF = leftRight $ proc _ -> do
>   rec c <- unique <<< textboxE "" <<< delay Nothing -< updateC
>       label "degrees Celsius = " -< ()
>       f <- unique <<< textboxE "" <<< delay Nothing -< updateF
>       label "degrees Fahrenheit" -< ()
>       let cNum = join $ fmap (readMaybe :: String -> Maybe Double) c
>           fNum = join $ fmap (readMaybe :: String -> Maybe Double) f
>           updateC = fmap (\f -> show $ round $ (f - 32) * (5/9)) fNum
>           updateF = fmap (\c -> show $ round $ c * (9/5) + 32) cNum
>   returnA -< ()
>
> tempConvert = runUI (400,24) "Temp Converter" tempCovertSF


---------------------------------------
------------ Flight Booker ------------
---------------------------------------

For the flight booker example, we make a few modifications to the 
given design.  First off, UISF does not currently have a built-in 
combobox widget, so we instead use a radio button widget.  Second, 
although it is possible to create custom text colors and backgrounds, 
this is not basic behavior or UISF, so we use a slightly different 
method for pointing out invalid data to the user.

One neat feature of UISF is its ability to dynamically add and remove 
widgets based on user input, a feature typically not found in arrowized 
FRP (or if found, more complicated and confusing then necessary).  We 
use this feature both to make the booking button inactive (we actually 
just remove it altogether) and to point out invalid date entries.  Note 
that this dynamic layout structure requires the use of a delay at any 
point where user data is used for layout changes.

To start, we will create a custom textbox widget that will only accept 
valid dates.  For invalid dates, it will add a label to the right 
indicating that the entry is invalid.

> timeInputTextbox :: TimeLocale -> String -> String -> UISF () (SEvent UTCTime)
> timeInputTextbox tl format start = leftRight $ proc _ -> do
>     t <- delay "" <<< textboxE start -< Nothing
>     let ret = readTimeMaybe tl format t
>     case ret of
>       Just _ -> returnA -< ret
>       Nothing -> label "invalid!" -< Nothing
>   where readTimeMaybe :: TimeLocale -> String -> String -> Maybe UTCTime
>         readTimeMaybe tl format s = case readsTime tl format s of
>                                       [(x, "")] -> Just x
>                                       _ -> Nothing

Note the use of the delay with the textboxE -- we need this because we 
will use the value t to determine whether to insert the label or not.

Note the clever use of unique and resetText.  We would like the display 
box that shows the booking confirmation to reset every time the user 
changes anything.  To achieve this, we create an event whenever choice, 
t1, or t2 change, and on those events, we set resultStr to the empty 
string.

> flightBookerSF :: TimeLocale -> UTCTime -> UISF () ()
> flightBookerSF tl currentTime = proc _ -> do
>     choice <- delay 0 <<< radio ["one-way flight","return flight"] 0 -< ()
>     t1 <- timeInputTextbox tl format (formatTime tl format currentTime) -< ()
>     t2 <- case choice of
>             1 -> timeInputTextbox tl format (formatTime tl format currentTime) -< ()
>             _ -> label "" -< Nothing
>     resetText <- unique -< (choice, t1, t2)
>     b <- if (choice == 0 && isJust t1) || (choice == 1 && verifyGreater t1 t2)
>          then do
>               b' <- edge <<< button "Book" -< ()
>               returnA -< if isJust resetText then Just "" else fmap (const $ outText tl format choice t1 t2) b'
>          else label "" -< Just "Please change your options to make a booking"
>     resultStr <- hold "" -< b
>     displayStr -< resultStr
>   where format ="%Y.%m.%d"
>         -- outText formats the data for a booking confirmation
>         outText tl format 0 (Just t1) _  = "You have booked a one-way flight on " 
>             ++ (formatTime tl format t1) ++ "."
>         outText tl format 1 (Just t1) (Just t2) = "You have booked a return flight leaving on " 
>             ++ (formatTime tl format t1) ++ " and returning on " ++ (formatTime tl format t2) ++ "."
>         outText _ _ _ _ _ = "ERROR!"
>         -- verifyGreater makes sure both times exist and that the first is less than the second
>         verifyGreater (Just t1) (Just t2) = t1 < t2
>         verifyGreater _ _ = False
> 
> flightBooker = getCurrentTime >>= \time -> runUI (800,200) "Flight Booker" (flightBookerSF defaultTimeLocale time)


---------------------------------------
---------------- Timer ----------------
---------------------------------------

The timer is very straightforward with UISF even though there is no 
built-in "gauge" widget.  We'll start by defining one by using the 
canvas' widget builder.  The widget will take the pair of 
(elapsed time, total duration) and draw a block of the appropriate 
size.  To use canvas', we supply a layout argument (stretchy in the 
horizontal direction but fixed to 30 pixels in the vertical direction).

> guage :: UISF (DeltaT, DeltaT) ()
> guage = arr Just >>> canvas' (makeLayout (Stretchy 0) (Fixed 30)) draw where
>   draw (x,t) (w,h) = block ((0,padding),(round $ x*(fromIntegral (w - 2*padding))/t,h-2*padding))

Next, we make a short helper function for keeping track of elapsed time.  
UISF provides "getTime", which provides the number of seconds since the 
GUI started; here we write getDeltaTime, which uses a simple "delay" 
operator to find how much time has gone by in the most recent clock cycle.

> getDeltaTime :: UISF () DeltaT
> getDeltaTime = proc _ -> do
>   t <- getTime -< ()
>   pt <- delay 0 -< t
>   returnA -< t - pt

With these two helpers, the program is a snap.  Note once again that 
since the elapsed time "e" is being used directly in the GUI's output, 
we must apply a delay to it to prevent an infinite recursion.

> timerGUISF :: UISF () ()
> timerGUISF = proc _ -> do
>     rec leftRight $ label "Elapsed Time:" >>> guage -< (e,d)
>         display -< e
>         leftRight $ label "Duration:" >>> display -< d
>         d <- hSlider (0,30) 4 -< ()
>         reset <- button "Reset" -< ()
>         dt <- getDeltaTime -< ()
>         e <- delay 0 -< case (reset, e >= d) of
>                           (True, _) -> 0
>                           (False, True) -> e
>                           _ -> e + dt
>     returnA -< ()
> 
> timerGUI = runUI (800,200) "Timer" timerGUISF


---------------------------------------
---------------- CRUD ----------------
---------------------------------------

For the CRUD example, we require a database in addition to the standard 
GUI tools.  We'll make a simple one out of a list and a NameEntry type

> type Database a = [a]
> data NameEntry = NameEntry {firstName :: String, lastName :: String}
> 
> instance Show NameEntry where
>     show (NameEntry f l) = l ++ ", " ++ f
> 
> instance Eq NameEntry where
>     (NameEntry f1 l1) == (NameEntry f2 l2) = f1 == f2 && l1 == l2

The delete and update helper functions below take an additional 
"filter function" argument.  When the database is viewed with a 
filter, the selected index may not match up directly with the 
database.  Therefore, the filtering function is supplied along with 
the index.

> deleteFromDB :: (a -> Bool) -> Int -> Database a -> Database a
> deleteFromDB _ _ [] = []
> deleteFromDB f i (x:xs) = case (f x, i == 0) of
>     (True, True)    -> xs
>     (True, False)   -> x:deleteFromDB f (i-1) xs
>     (False, _)      -> x:deleteFromDB f i xs
>
> updateDB :: (a -> Bool) -> Int -> a -> Database a -> Database a
> updateDB _ _ _ [] = []
> updateDB f i a (x:xs) = case (f x, i == 0) of
>     (True, True)    -> a:xs
>     (True, False)   -> x:updateDB f (i-1) a xs
>     (False, _)      -> x:updateDB f i a xs


We'll even create some default names to populate our database.

> defaultnames :: Database NameEntry
> defaultnames = [
>     NameEntry "Paul" "Hudak",
>     NameEntry "Dan" "Winograd-Cort",
>     NameEntry "Donya" "Quick"]

The CRUD example has a much more complex layout than the previous 
examples we have dealt with so far.  One way to simplify it would 
be to make a few different components, each of which is a combination 
of widgets, and then link them together.  Each component could have a 
different layout, and when combined, the overall layout effect is 
achieved.

Another option, which we will illustrate here, is to use banana brackets
Banana brackets allow one to apply a 
transformation function to a "sub-arrow" -- here, we use them to 
apply layout transformations to specific components of the GUI.  
Unfortunately, banana brackets were made for arrows, not UISF, and 
the variables that are defined within them are not in scope outside.  
Thus, we have a somewhat ugly result, where the last line in the 
brackets is a returnA of all the variables, which are then saved 
outside of the brackets.  It's better than if we separated everything, 
in which case the banana bracketed code would not inherit its parent's 
scope either, but still, it is less than ideal.

We start by asking for the filter text and then using banana brackets 
to define a "leftRight" layout portion.

> crudSF :: Database NameEntry -> UISF () ()
> crudSF initnamesDB = proc _ -> do
>   rec
>     fStr <- leftRight $ label "Filter text: " >>> textboxE "" -< Nothing
>     (i, db, fdb, nameData) <- (| leftRight (do

This leftRight portion will have a listbox on the left and then a 
topDown portion on the right that will be for entering name data.

>         rec i <- listbox -< (fdb, i')
>             db <- delay initnamesDB -< db'
>             let fdb = filter (filterFun fStr) db
>         nameData <- (| topDown (do

We add two textboxes for the first name and surname strings and 
then set them to update whenever one of the listbox items is selected.

>             rec nameStr <- leftRight $ label "Name:    " >>> textboxE "" -< nameStr'
>                 surnStr <- leftRight $ label "Surname: " >>> textboxE "" -< surnStr'
>                 iUpdate <- unique -< i
>                 let nameStr' = fmap (const $ firstName ((filter (filterFun fStr) db') `at` i')) iUpdate
>                     surnStr' = fmap (const $ lastName  ((filter (filterFun fStr) db') `at` i')) iUpdate
>             returnA -< NameEntry nameStr surnStr) |)
>         returnA -< (i, db, fdb, nameData)) |)

Finally, we make the three buttons, which we can do all at once with 
arrow combinators.  Based on button presses, we update the database.

>     buttons <- leftRight $ (edge <<< button "Create") &&& 
>                            (edge <<< button "Update") &&& 
>                            (edge <<< button "Delete") -< ()
>     let (db', i') = case buttons of
>             (Just _, (_, _))             -> (db ++ [nameData], length fdb)
>             (Nothing, (Just _, _))       -> (updateDB (filterFun fStr) i nameData db, i)
>             (Nothing, (Nothing, Just _)) -> (deleteFromDB (filterFun fStr) i db,
>                                             if i == length fdb - 1 then length fdb - 2 else i)
>             _ -> (db, i)
>   returnA -< ()
>   where
>     filterFun str name = and (map (\s -> isInfixOf s (map toLower $ show name)) (words (map toLower str)))
>     lst `at` index = if index >= length lst || index < 0 then NameEntry "" "" else lst!!index
> 
> crud = runUI (450, 400) "CRUD" (crudSF defaultnames)


---------------------------------------
------------ Circle Drawer ------------
---------------------------------------

