/*
** The include for the Steambot Announcements and events plugin.
*/
#if defined _Steambot_Announcements_included
 #endinput
#endif
#define _Steambot_Announcements_included

/**
 * Allows plugins to post announcements or events to the steamgroup via the steambot.
 *
 * @param client		Client executing the announcement or event, 0 for console.
 * @param sTitle		The title of the announcement or event.
 * @param sBody			The body of the announcement or event.
 * @return				True if successful, false otherwise.
 */
native bool Steambot_Announce(int client, const char[] sTitle, const char[] sBody);

#if !defined REQUIRE_PLUGIN
public __pl_Steambot_Announcements_SetNTVOptional()
{
	MarkNativeAsOptional("Steambot_Announce");
}
#endif

public SharedPlugin __pl_Steambot_Announcements =
{
	name = "Steambot-Announcements",
	file = "Steambot-Announcements.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};
