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
native int AddAttributeToConfig(int itemId, int attribute, float modifier, int mode, bool addToConfig);

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