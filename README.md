![Mule Logo](/icons/donkey-icon.png)
# Mule
Mule addon by CubeNicke, for Vanilla WoW.  To make raiding consumables managable, this by helping with tasks at mail, bank and vendor, moving items back and forth between characters.
The addon helps with supplying a raider with cons after a raid and a farmer toon to unload farmed items to Mule toons. The normal usage when you have been out farming is to go to the mailbox and just press Alt Key for a couple of seconds then all farmed stuff will be sent to registred mule for each item. Another case is to after raid logon to the main mule character and go to mail and do a '/mule supply <raider>') 
It's useful to have a main mule supplier on same account and then several mules that supplies the main mule on other accounts. Mule helps to split the banking issue between several characters with ease, The key is to register what mule that should be recipient for each item group/item or type
  
The three typical roles are Raider, Farmer and Mule.  

## Raider
Wants to get refilled with cons from Mules and or from bank/vendor, can also be useful to have different profiles for different consumable/gear setups. If a supplier is not on same account the raider needs to be online so supplier knows what to supply with.  
The raider must create a profile that contains the items that should exists when fully equipped with consumables and gear. (i.e. fill your bags with all gears and cons for a naxx raid and then use /mule profile naxx, the profile can be edited later with /mule profiles command.)

    /mule profile <name>

To edit profiles, drag items to a profile, use Alt-click to remove items or profiles. Use +/- on items to set amount, when dragging an item to a profile a stack of that item will be added.

    /mule profiles
	
To refill consumables when at bank or at a vendor

    /mule supply
	
To register a supplier(i.e a mule), this is needed to make sure that the supplier is authenticated

    /mule register <mule>

Have profiles for each raid situation and switch between them, remember that equipped items are not in any profile and if you switch profiles those won't be included.


## Farmer
Wants to set a profile with current items then go farming which will be unloaded to vendor or to Mule at mailbox. It's important to have a profile active before farming since items in profile won't be sent to mules. 
To update the "base" profile  

    /mule base

To mail or sell marked items to vendor or put them in bank

    /mule unload

To register a new mule  

    /mule register <mule name>

To edit mules or the items sent to the mule, drag item from your bags to the mule and all items of that kind that not is in active profile will be sent to the mule. delete items/filters/mules with Alt-click.

    /mule mules

To add a filter to a mule, a filter can be a Type i.e. "Armor" to send all armor gear to the toon, not that gray items will never be mailed when filtering on type.

	/mule <mule name> <filter>

## Mule
The role of a mule is to supply Raiders with consumables for raiding, toons doing their trade or farmers with consumables.  
At mailbox, send items to fill the Raiders inventory to match active profile, note that raider must be on same account or online and not in party/raid, since mule will invite raider to a party if not on same account.

    /mule supply <raider>

## Profiles
A profile is a set of items/gears that suit a purpose, every character gets a default profile 'base'. Show the profiles view to edit/delete profiles and select currently active one.  

## Filters
Item name or Item type or "Alchemy", "Enchanting", "Tailoring", "Leatherworking", "Engineering", "Blacksmithing", "Cooking"  

Common types used to filter:
Weapon
Armor

## Keybinds
Keybind can be done to 'show profiles' and 'show mule'


## Reference
```
/mule activate <profile> - Set <profile> as active profile, can also click on profile in profiles view
/mule addworn - Add worn items to current profile
/mule base - Update "base" profile
/mule diff - output items that is missing from active profile
/mule excess - output stuff that isn't included in active profile
/mule help [<command>] - give help
/mule mules - Show Mules and their filters
/mule profile <profile> - Will create profile <profile>.
/mule profiles - Show profiles and their items
/mule register <name> - Create a mule 
/mule remove <profile> - Remove a profile
/mule supply [<name>] - Supply a character or self with missing items.
/mule unload - Distribute items to registred mules.
/mule unregister <mule> - remove a mule
/mule <item>|<id> - Give info regarding item
/mule <mule> <filter> - Set a filter for a mule, can be a item or a item type.
for debugging
/mule debug - toggle debug output from mule
```

/CubeNicke aka Yrrol@vanillagaming