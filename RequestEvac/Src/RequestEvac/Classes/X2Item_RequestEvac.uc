class X2Item_RequestEvac extends X2Item;

// Create a dummy item that will serve as the XCGS_RequestItem template name.
// Mostly just to prevent redscreens and other warnings, since there always must be a ~~Lich King~~ template name.

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;
	local X2ItemTemplate 		Template;

	`CREATE_X2TEMPLATE(class'X2ItemTemplate', Template, 'BD_RequestEvac_DummyItem');

	Template.ItemCat = 'unlimited';

	Templates.AddItem(Template);

	return Templates;
}
