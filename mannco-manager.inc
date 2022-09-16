/** Double-include prevention */
#if defined _manncomanager_included_
  #endinput
#endif
#define _manncomanager_included_

/*
 *
 * Adds the attribute to the specified item until further notice.
 * item: the item id
 * attribute: the attribute id
 * modifier: the modifier flag to use
 * mode: if -1, override.
 * if 0, item default.
 * if 1, add (additive, additive percentage)
 * if 2, multiply (percentage, inverted percentage)
 * addToConfig: whether or not to add the value to a configuration file, for use after a restart
 * */
native int ApplyItemModification(int itemId, int attribute, float modifier, int mode, char[] logLabel);

/*
 *
 * Gets the current value of the provided attribute, static or not.
 * item: the item id
 * attribute: the attribute id
 * */
native float QueryAttributeValue(int itemId, int attribute, int mode);

/*
 *
 * Gets what the new value of the provided attribute would be, if applied. The change is not applied.
 * item: the item id
 * attribute: the attribute id
 * modifier: the modifier flag to use
 * mode: if -1, override.
 * if 0, item default.
 * if 1, add (additive, additive percentage)
 * if 2, multiply (percentage, inverted percentage)
 * */
native float QueryAttributeEffect(int itemId, int attribute, float modifier, int mode);

/*
 *
 * Prints out a list of attributes in console to the specified user, for the specified weapon.
 * If there are no changed attributes, the user will be told this instead.
 * */
 native void DumpAttributes(int itemId, int[] attributes, float[] values, int size);
 
/*
 *
 * Get whether or not the specified item exists
 * */
 native bool M_Item_IsKnown(int itemId);
 
/*
 *
 * Get whether or not the specified item exists
 * */
 native bool M_Attrib_IsKnown(int attribId);
 
/*
 *
 * Gets the parent, until a root node is hit. If this is a root node, it will return itself.
 * */
 native int M_Item_GetParent(int itemId);
 
/*
 *
 * Gets the parent, until a root node is hit. If this is a root node, it will return itself.
 * */
 native int M_Attrib_GetParent(int attribId);
 
/*
 *
 * Get the debug name of an item. Usually, this is the internal debug name, but these can be changed for mannco's uses.
 * */
 native void M_Item_GetDebugName(int itemId, char[] name);
 
/*
 *
 * Get the debug name of an attribute. Usually, this is the internal debug name, but these can be changed for mannco's uses.
 * */
 native void M_Attrib_GetDebugName(int attribId, char[] name);
 
/*
 *
 * Puts the slot for the specified item in the provided array.
 * */
 native void M_Item_GetSlot(int itemId, char[] slot);
 
/*
 *
 * Gets a magic number representing the type of operation this attribute applies.
 * Additional values are used:
 * additive_percentage: 3 (addition with smaller default units)
 * inverted_percentage: 4 (multiplication with good/bad reversed)
 * */
 native float M_Attrib_GetDatatype(int attribId);
 
/*
 *
 * Gets the maximum increase this attribute can get in a single go.
 * This value is used for balancing reasons, and is only a strong suggestion.
 * */
 native float M_Attrib_GetMaxIncrease(int attribId);
 
/*
 *
 * Gets the maximum decrease this attribute can get in a single go.
 * This value is used for balancing reasons, and is only a strong suggestion.
 * */
 native float M_Attrib_GetMaxDecrease(int attribId);
 
/*
 *
 * Gets the interval for which this can increase.
 * The default interval of 1 means a range of [-15, 15]. An interval value of 0.1 changes the range to [-1.5, 1.5].
 * This value is used for balancing reasons, and is only a strong suggestion.
 * */
 native float M_Attrib_GetInterval(int attribId);
 
/*
 *
 * Gets the highest possible value for this attribute.
 * This value is a hard limit; there is either no effect or very nasty bugs when broken.
 * */
 native float M_Attrib_GetMaximum(int attribId);
 
/*
 *
 * Gets the lowest possible value for this attribute.
 * This value is a hard limit; there is either no effect or very nasty bugs when broken.
 * */
 native float M_Attrib_GetMinimum(int attribId);
 
/*
 *
 * Tests whether or not the item can have the provided attribute, based on its flags.
 * */
 native bool M_FlagsAgree(int itemId, int attribId);