/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

using Gtk;
using Gee;
using Notify;

public class BeatBox.LibraryWindow : LibraryWindowInterface, Gtk.Window {

	// signals
	public signal void playPauseChanged ();

	public static Granite.Application app { get; private set; }

	public BeatBox.LibraryManager lm { get; private set; }
	public BeatBox.Settings settings { get; private set; }

	private LastFM.SimilarMedias similarMedias;
	private BeatBox.MediaKeyListener mkl;

	private HashMap<int, Device> music_welcome_screen_keys;


	/* Core views. Some will be probably split into plugins in future versions */
	private ViewWrapper music_library_view;

#if HAVE_PODCASTS
	private ViewWrapper podcast_library_view;
#endif

#if HAVE_INTERNET_RADIO
	private ViewWrapper radio_library_view;
#endif

	private bool queriedlastfm; // whether or not we have queried last fm for the current media info
	private bool media_considered_played; // whether or not we have updated last played and added to already played list
	private bool added_to_play_count; // whether or not we have added one to play count on playing media
	private bool tested_for_video; // whether or not we have tested if media is video and shown video
	private bool scrobbled_track;

	public bool dragging_from_music { get; set; }

	public bool initialization_finished { get; private set; }

	private VBox verticalBox;

	public Notebook main_views { get; private set; }

	public DrawingArea videoArea  { get; private set; }
	public HPaned sourcesToMedias { get; private set; } //allows for draggable

	public HPaned mediasToInfo { get; private set; } // media info pane
	private ScrolledWindow sideTreeScroll;

	public SideTreeView sideTree { get; private set; }

	private InfoPanel infoPanel;

	private Toolbar topControls;
	public ToolButton previousButton { get; private set; }
	public ToolButton playButton { get; private set; }
	public ToolButton nextButton { get; private set; }

	public ToggleButton column_browser_toggle { get; private set; }

	public TopDisplay topDisplay { get; private set; }

	public Granite.Widgets.ModeButton viewSelector { get; private set; }
	public Granite.Widgets.SearchBar  searchField  { get; private set; }

	private StatusBar statusBar;

	private SimpleOptionChooser addPlaylistChooser;
	private SimpleOptionChooser shuffleChooser;
	private SimpleOptionChooser repeatChooser;
	private SimpleOptionChooser infoPanelChooser;
	private SimpleOptionChooser eq_option_chooser;

	// basic file stuff
	private Gtk.Menu settingsMenu;
	private Gtk.Menu libraryOperationsMenu;
	private ImageMenuItem libraryOperations;
	private Gtk.MenuItem fileImportMusic;
	private Gtk.MenuItem fileRescanMusicFolder;
	private ImageMenuItem editPreferences;

	public Notify.Notification notification { get; private set; }

	public LibraryWindow(Granite.Application app, BeatBox.Settings settings, string[] args) {
		this.app = app;
		this.settings = settings;

		// Init libnotify
		Notify.init ("noise");

		// Load icon information
		Icons.init ();

		//this is used by many objects, is the media backend
		lm = new BeatBox.LibraryManager(settings, this, args);

		//various objects
		music_welcome_screen_keys = new HashMap<int, Device>();
		similarMedias = new LastFM.SimilarMedias(lm);
		mkl = new MediaKeyListener(lm, this);

#if HAVE_INDICATE
#if HAVE_DBUSMENU
		message("Initializing MPRIS and sound menu\n");
		var mpris = new BeatBox.MPRIS(lm, this);
		mpris.initialize();
#endif
#endif

		dragging_from_music = false;

		this.lm.player.end_of_stream.connect(end_of_stream);
		this.lm.player.current_position_update.connect(current_position_update);
		//FIXME? this.lm.player.media_not_found.connect(media_not_found);
		this.lm.music_counted.connect(musicCounted);
		this.lm.music_added.connect(musicAdded);
		this.lm.music_imported.connect(musicImported);
		this.lm.music_rescanned.connect(musicRescanned);
		this.lm.progress_notification.connect(progressNotification);
		this.lm.medias_updated.connect(medias_updated);
		this.lm.media_played.connect(media_played);
		this.lm.playback_stopped.connect(playback_stopped);
		this.lm.dm.device_added.connect(device_added);
		this.lm.dm.device_removed.connect(device_removed);
		this.similarMedias.similar_retrieved.connect(similarRetrieved);

		this.destroy.connect (on_quit);

		if(lm.media_count() == 0 && settings.getMusicFolder() == "") {
			message("First run.\n");
		}
		else {
			lm.clearCurrent();

			// make sure we don't re-count stats
			if((int)settings.getLastMediaPosition() > 5)
				queriedlastfm = true;
			if((int)settings.getLastMediaPosition() > 30)
				media_considered_played = true;
			if(lm.media_active && (double)((int)settings.getLastMediaPosition()/(double)lm.media_info.media.length) > 0.90)
				added_to_play_count = true;

			// rescan on startup
			/*lm.rescan_music_folder();*/
		}

		/*if(!File.new_for_path(settings.getMusicFolder()).query_exists() && settings.getMusicFolder() != "") {
			doAlert("Music folder not mounted", "Your music folder is not mounted. Please mount your music folder before using BeatBox.");
		}*/
	}

	public void build_ui() {
		// simple message to terminal
		message ("Building user interface\n");

		// set window min/max
		Gdk.Geometry geo = Gdk.Geometry();
		geo.min_width = 700;
		geo.min_height = 400;
		set_geometry_hints(this, geo, Gdk.WindowHints.MIN_SIZE);

		// set the size based on saved gconf settings
		set_default_size(settings.getWindowWidth(), settings.getWindowHeight());
		

		// set the title
		set_title("Noise");

		// set the icon
		set_icon(Icons.BEATBOX.render (IconSize.MENU, null));

		/* Initialize all components */
		verticalBox = new VBox(false, 0);
		sourcesToMedias = new HPaned();
		mediasToInfo = new HPaned();
		main_views = new Notebook ();
		videoArea = new DrawingArea();

		sideTree = new SideTreeView(lm, this);
		sideTreeScroll = new ScrolledWindow(null, null);
		libraryOperations = new ImageMenuItem.from_stock("library-music", null);
		libraryOperationsMenu = new Gtk.Menu();
		fileImportMusic = new Gtk.MenuItem.with_label(_("Import to Library"));
		fileRescanMusicFolder = new Gtk.MenuItem.with_label(_("Rescan Music Folder"));
		editPreferences = new ImageMenuItem.from_stock(Gtk.Stock.PREFERENCES, null);
		settingsMenu = new Gtk.Menu();
		topControls = new Toolbar();
		previousButton = new ToolButton.from_stock(Gtk.Stock.MEDIA_PREVIOUS);
		playButton = new ToolButton.from_stock(Gtk.Stock.MEDIA_PLAY);
		nextButton = new ToolButton.from_stock(Gtk.Stock.MEDIA_NEXT);
		topDisplay = new TopDisplay(lm);
		
		column_browser_toggle = new ToggleButton ();
		viewSelector = new Granite.Widgets.ModeButton();
		searchField = new Granite.Widgets.SearchBar(_("Search..."));

		infoPanel = new InfoPanel(lm, this);
		statusBar = new StatusBar();

		var add_playlist_image = Icons.render_image ("list-add-symbolic", IconSize.MENU);
		var shuffle_on_image = Icons.SHUFFLE_ON.render_image (IconSize.MENU);
		var shuffle_off_image = Icons.SHUFFLE_OFF.render_image (IconSize.MENU);
		var repeat_on_image = Icons.REPEAT_ON.render_image (IconSize.MENU);
		var repeat_off_image = Icons.REPEAT_OFF.render_image (IconSize.MENU);
		var info_panel_show = Icons.PANE_SHOW_SYMBOLIC.render_image (IconSize.MENU);
		var info_panel_hide = Icons.PANE_HIDE_SYMBOLIC.render_image (IconSize.MENU);
		var eq_show_image = Icons.EQ_SYMBOLIC.render_image (IconSize.MENU);
		var eq_hide_image = Icons.EQ_SYMBOLIC.render_image (IconSize.MENU);

		addPlaylistChooser = new SimpleOptionChooser.from_image (add_playlist_image);
		shuffleChooser = new SimpleOptionChooser.from_image (shuffle_on_image, shuffle_off_image);
		repeatChooser = new SimpleOptionChooser.from_image (repeat_on_image, repeat_off_image);
		infoPanelChooser = new SimpleOptionChooser.from_image (info_panel_hide, info_panel_show);
		eq_option_chooser = new SimpleOptionChooser.from_image (eq_hide_image, eq_show_image);

		repeatChooser.setTooltip (_("Disable Repeat"), _("Enable Repeat"));
		shuffleChooser.setTooltip (_("Disable Shuffle"), _("Enable Shuffle"));
		infoPanelChooser.setTooltip (_("Hide Info Panel"), _("Show Info Panel"));
		addPlaylistChooser.setTooltip (_("Add Playlist"));
		eq_option_chooser.setTooltip (_("Hide Equalizer"), _("Show Equalizer"));

		statusBar.insert_widget (addPlaylistChooser, true);
		statusBar.insert_widget (new Gtk.Box (Orientation.HORIZONTAL, 12), true);
		statusBar.insert_widget (shuffleChooser, true);
		statusBar.insert_widget (repeatChooser, true);
		statusBar.insert_widget (eq_option_chooser);
		statusBar.insert_widget (infoPanelChooser);

		notification = new Notify.Notification ("", null, null);

		// Set properties of various controls
		sourcesToMedias.set_position(settings.getSidebarWidth());
		mediasToInfo.set_position((lm.settings.getWindowWidth() - lm.settings.getSidebarWidth()) - lm.settings.getMoreWidth());

		// ADD MAIN VIEWS
		build_main_views ();

		// ADD PLAYLIST VIEWS
		load_playlists ();

#if HAVE_STORE
		// LOAD MUSIC STORE VIEW
		load_default_store ();
#endif

		sideTreeScroll = new ScrolledWindow(null, null);
		//FIXME: don't scroll horizontally
		sideTreeScroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		sideTreeScroll.add(sideTree);

		/* create appmenu menu */
		libraryOperationsMenu.append(fileImportMusic);
		libraryOperationsMenu.append(fileRescanMusicFolder);
		libraryOperations.submenu = libraryOperationsMenu;
		libraryOperations.set_label(_("Library"));

		settingsMenu.append(libraryOperations);
		settingsMenu.append(new SeparatorMenuItem());
		settingsMenu.append(editPreferences);

		fileImportMusic.activate.connect(fileImportMusicClick);
		fileRescanMusicFolder.activate.connect(fileRescanMusicFolderClick);

		editPreferences.set_label(_("Preferences"));

		editPreferences.activate.connect(editPreferencesClick);

		repeatChooser.appendItem(_("Off"));
		repeatChooser.appendItem(_("Song"));
		repeatChooser.appendItem(_("Album"));
		repeatChooser.appendItem(_("Artist"));
		repeatChooser.appendItem(_("All"));

		shuffleChooser.appendItem(_("Off"));
		shuffleChooser.appendItem(_("All"));

		infoPanelChooser.appendItem(_("Hide"));
		infoPanelChooser.appendItem(_("Show"));

		eq_option_chooser.appendItem(_("Hide"));
		eq_option_chooser.appendItem(_("Show"));

		repeatChooser.setOption(settings.getRepeatMode());
		shuffleChooser.setOption(settings.getShuffleMode());
		infoPanelChooser.setOption(settings.getMoreVisible() ? 1 : 0);
		eq_option_chooser.setOption(0);

		// Add controls to the GUI
		add(verticalBox);
		verticalBox.pack_start(topControls, false, true, 0);
		verticalBox.pack_start(videoArea, true, true, 0);
		verticalBox.pack_start(sourcesToMedias, true, true, 0);
		verticalBox.pack_end(statusBar, false, true, 0);

		var column_toggle_bin = new ToolItem();
		var topDisplayBin = new ToolItem();
		var viewSelectorBin = new ToolItem();
		var searchFieldBin = new ToolItem();

		viewSelector.append(Icons.VIEW_ICONS.render_image (IconSize.MENU));
		viewSelector.append(Icons.VIEW_DETAILS.render_image (IconSize.MENU));

		column_browser_toggle.set_image (Icons.VIEW_COLUMN.render_image (IconSize.MENU));

		// Tweak view selector's size
		viewSelector.margin_left = 12;
		viewSelector.margin_right = 8;

		viewSelector.valign = column_browser_toggle.valign = Gtk.Align.CENTER;
		
		viewSelectorBin.add(viewSelector);

		column_toggle_bin.add (column_browser_toggle);

		topDisplayBin.add(topDisplay);
		topDisplayBin.set_expand(true);

		topDisplay.margin_left = 30;
		topDisplay.margin_right = 30;

		searchFieldBin.add(searchField);
		searchFieldBin.margin_right = 12;

		// Set theming
		topControls.get_style_context().add_class(STYLE_CLASS_PRIMARY_TOOLBAR);
		sourcesToMedias.get_style_context().add_class ("sidebar-pane-separator");

		topControls.set_vexpand (false);
		topControls.set_hexpand (true);

		topControls.insert(previousButton, -1);
		topControls.insert(playButton, -1);
		topControls.insert(nextButton, -1);
		topControls.insert(viewSelectorBin, -1);
		topControls.insert(column_toggle_bin, -1);
		topControls.insert(topDisplayBin, -1);
		topControls.insert(searchFieldBin, -1);
		topControls.insert(app.create_appmenu(settingsMenu), -1);

		var music_folder_icon = Icons.MUSIC_FOLDER.render (IconSize.DIALOG, null);
		music_library_view.welcome_screen.append_with_pixbuf(music_folder_icon, _("Locate"), _("Change your music folder."));

		// Hide notebook tabs and border
		main_views.show_tabs = false;
		main_views.show_border = false;
		
		mediasToInfo.pack1(main_views, true, false);
		mediasToInfo.pack2(infoPanel, false, false);

		sourcesToMedias.pack1(sideTreeScroll, false, true);
		sourcesToMedias.pack2(mediasToInfo, true, true);

		// add mounts to side tree view
		lm.dm.loadPreExistingMounts();

		int i = settings.getLastMediaPlaying();
		if(i != 0 && lm.media_from_id(i) != null && File.new_for_uri(lm.media_from_id(i).uri).query_exists()) {
			lm.media_from_id(i).resume_pos;
			lm.playMedia(i, true);
		}
		else {
			// don't show info panel if nothing playing
			infoPanel.set_visible(false);
		}

		/* Connect events to functions */
		music_library_view.welcome_screen.activated.connect(music_welcome_screen_activated);
		previousButton.clicked.connect(previousClicked);
		playButton.clicked.connect(playClicked);
		nextButton.clicked.connect(nextClicked);

		addPlaylistChooser.button_press_event.connect(addPlaylistChooserOptionClicked);
		eq_option_chooser.option_changed.connect(eq_option_chooser_clicked);

		repeatChooser.option_changed.connect(repeatChooserOptionChanged);
		shuffleChooser.option_changed.connect(shuffleChooserOptionChanged);
		infoPanelChooser.option_changed.connect(infoPanelChooserOptionChanged);

		searchField.activate.connect(searchFieldActivate);

		/* set up drag dest stuff */
		drag_dest_set(this, DestDefaults.ALL, {}, Gdk.DragAction.MOVE);
		Gtk.drag_dest_add_uri_targets(this);
		drag_data_received.connect(dragReceived);

		initialization_finished = true;

		show_all();
		update_sensitivities();

		sideTree.resetView();

		if(lm.media_active) {
			if(settings.getShuffleMode() == LibraryManager.Shuffle.ALL) {
				lm.setShuffleMode(LibraryManager.Shuffle.ALL, true);
			}
		}


		infoPanel.set_visible (lm.settings.getMoreVisible());


		// Now set the selected view
		viewSelector.selected = settings.getViewMode();

		searchField.set_text(lm.settings.getSearchString());

		viewSelector.mode_changed.connect( () => {
			if (viewSelector.sensitive)
				settings.setViewMode(viewSelector.selected);

			// In case the user switched to video mode ...			
			if (viewSelector.selected == 2) // Video
				update_sensitivities();
		});

		if(lm.song_ids().size == 0)
			setMusicFolder(Environment.get_user_special_dir(UserDirectory.MUSIC));
		
		// Redirect key presses to the search box. If it causes problems, move inside ViewWrapper.vala
		this.key_press_event.connect( (event) => {
			if(Regex.match_simple("[a-zA-Z0-9]", event.str) && searchField.sensitive && !searchField.has_focus) {
				searchField.grab_focus();
			}
			return false;
		});
	}

	public static Gtk.Alignment wrap_alignment (Gtk.Widget widget, int top, int right, int bottom, int left) {
		var alignment = new Gtk.Alignment(0.0f, 0.0f, 1.0f, 1.0f);
		alignment.top_padding = top;
		alignment.right_padding = right;
		alignment.bottom_padding = bottom;
		alignment.left_padding = left;

		alignment.add(widget);
		return alignment;
	}


	/**
	 * Description:
	 * Builds the views (view wrapper) and adds the respective element to the sidebar TreeView.
	 *
	 * @param tree The sidebar tree to build it on [if NULL is passed it uses the default tree]
	 * @param hint The type of View Wrapper
	 * @param view_name The name of the item in the sidebar
	 * @param media indexes of the media to show in the view
	 * @param sort_column treeview column used to sort list items
	 * @param sort_column column used to sort the list. Default: "" [allow-none]
	 * @param sort_type sort type (ascending, descending, etc.) Default: 0 [allow-none]
	 */
	public ViewWrapper add_view (SideTreeView? tree, ViewWrapper.Hint hint, string view_name,
	                              Collection<int> media, string sort_column = "",
	                              Gtk.SortType sort_dir = 0, int id = -1)
	{
		if (tree == null)
			tree = sideTree; /* if NULL is passed we use the default sidebar tree */

		var view_wrapper = new ViewWrapper (this, media, sort_column, sort_dir, hint, id);

		tree.add_item (view_wrapper, view_name);

		/* Pack view wrapper into the main views */
		if (add_to_main_views(view_wrapper) == -1)
			critical ("Failed to append view '%s' to Noise's main views", view_name);

		return view_wrapper;
	}

	/**
	 * Sets the given view as the active item
	 */
	public void set_active_view (Gtk.Widget view) {
		if (!initialization_finished)
			return;
		
		int view_index = main_views.page_num (view);
		
		if (view_index < 0) {
			critical ("Cannot set " + view.name + " as the active view");
			return;
		}

		// Hide album list view if there's one
		var selected_view = get_current_view_wrapper ();
		if (selected_view is ViewWrapper) {
			if ((selected_view as ViewWrapper).has_album_view)
				((selected_view as ViewWrapper).album_view as AlbumView).album_list_view.hide();
		}

		// GtkNotebooks don't show hidden widgets. Make sure we show the view just in case ...
		view.show_all ();

		// We need to set this view as the current page before even attempting to call
		// the set_as_current_view() method. This also makes the switching faster ;)
		main_views.set_current_page (view_index);

		if (view is ViewWrapper) {
			((ViewWrapper)view).set_as_current_view();
		}
#if HAVE_STORE
		else if(view is Store.StoreView) {
			((Store.StoreView)view).setIsCurrentView(true);
		}
#endif
		else if(view is DeviceView) {
			DeviceView dv = (DeviceView)view;
			dv.set_as_current_view ();
		}
	}

	/**
	 * Appends a widget to the main views.
	 *
	 * WARNING: Don't use this method directly. add_view() and add_custom_view() are meant for that.
	 *
	 * @return the index of the view in the view container
	 */
	public int add_to_main_views (Gtk.Widget view) {
		return main_views.append_page (view);
	}

	/**
	 * Description:
	 * Builds the views (view wrapper) and adds the respective element to the sidebar TreeView.
	 *
	 * @param name The name of the item in the sidebar
	 * @param widget Widget containing the custom view
	 * @param tree The sidebar tree to build it on [if NULL is passed it uses the default tree]
	 *
	 * TODO: add plugin hook and update LibraryWindowInterface.
	 * TODO: Add option to pass an icon (needed by plugins).
	 *
	 * IMPORTANT: Currently every item added through this method will be put under the Network category
	 */
	public ViewWrapper add_custom_view (string name, Gtk.Widget widget, SideTreeView? tree = null) {
		if (tree == null)
			tree = sideTree; /* if NULL is passed we use the default sidebar tree */

		var view_wrapper = new ViewWrapper.with_view (widget);

		tree.add_item (view_wrapper, name);

		/* Pack view wrapper into the main views */
		int view_index = add_to_main_views (view_wrapper);

		if (view_index == -1)
			critical ("Failed to append view '%s' to Noise's main views", name);

		return view_wrapper;
	}

	/**
	 * Builds and sets up the default Noise views. That includes main sidebar elements
	 * and categories, which at the same time wrap treeviews, icon views, welcome screens, etc.
	 */
	private void build_main_views () {
		debug ("Building main views ...");

		// Add Music Library View
		music_library_view = add_view (null, ViewWrapper.Hint.MUSIC, _("Music"), lm.media_ids (), lm.music_setup.sort_column, lm.music_setup.sort_direction);

#if HAVE_PODCASTS
		// Add Podcast Library View
		podcast_library_view = add_view (null, ViewWrapper.Hint.PODCAST, _("Podcasts"), lm.podcast_ids ());
#endif

#if HAVE_INTERNET_RADIO
		// Add Internet Radio View
		radio_library_view = add_view (null, ViewWrapper.Hint.STATION, _("Internet Radio"), lm.station_ids(), lm.station_setup.sort_column, lm.station_setup.sort_direction);
#endif

		// Add Similar playlist. FIXME: This is part of LastFM and shouldn't belong to the core in the future
		add_view (null, ViewWrapper.Hint.SIMILAR, _("Similar"), new LinkedList<int>(), lm.similar_setup.sort_column, lm.similar_setup.sort_direction);

		// Add Queue view
		add_view (null, ViewWrapper.Hint.QUEUE, _("Queue"), lm.queue (), lm.queue_setup.sort_column, lm.queue_setup.sort_direction);

		// Add History view
		add_view (null, ViewWrapper.Hint.HISTORY, _("History"), lm.already_played (), lm.history_setup.sort_column, lm.history_setup.sort_direction);

		debug ("Done with main views.");
	}

	private void load_playlists () {
		debug ("Loading playlists");
		
		// load smart playlists
		foreach(SmartPlaylist p in lm.smart_playlists()) {
			addSideListItem(p);
		}

		// load playlists
		foreach(Playlist p in lm.playlists()) {
			addSideListItem(p);
		}

		debug ("Finished loading playlists");
	}

#if HAVE_STORE
	private void load_default_store () {
		if (Option.HAVE_STORE) {
			var storeView = new Store.StoreView(lm, this);
			add_custom_view (_("Music Store"), storeView);
		}
	}
#endif

	public void addSideListItem(GLib.Object o) {
		TreeIter item = sideTree.library_music_iter; //just a default
		ViewWrapper vw = null;

		// p.view_wrapper = add_view... is something that we should probably bake inside
		// BeatBox.Playlist and BeatBox.SmartPlaylist's constructors. It should be
		// optional though.
		if(o is Playlist) {
			Playlist p = (Playlist)o;

			p.view_wrapper = add_view (null, ViewWrapper.Hint.PLAYLIST, p.name, lm.medias_from_playlist(p.rowid),
			           p.tvs.sort_column, p.tvs.sort_direction, p.rowid);
		}
		else if(o is SmartPlaylist) {
			SmartPlaylist p = (SmartPlaylist)o;

			p.view_wrapper = add_view (null, ViewWrapper.Hint.SMART_PLAYLIST, p.name, lm.medias_from_smart_playlist(p.rowid),
			          p.tvs.sort_column, p.tvs.sort_direction, p.rowid);
		}
		/* XXX: Migrate this code to the new API
		 * Definitely not doing this for 1.0
		 */
		else if(o is Device) {
			Device d = (Device)o;

			if(d.getContentType() == "cdrom") {
				vw = new DeviceViewWrapper(this, d.get_medias(), "Track", Gtk.SortType.ASCENDING, ViewWrapper.Hint.CDROM, -1, d);
				item = sideTree.addSideItem(sideTree.devices_iter, d, vw, d.getDisplayName(), ViewWrapper.Hint.CDROM);
				add_to_main_views (vw);
			}
			else {
				debug ("adding ipod device view with %d\n", d.get_medias().size);
				DeviceView dv = new DeviceView(lm, d);
				//vw = new DeviceViewWrapper(this, d.get_medias(), "Artist", Gtk.SortType.ASCENDING, ViewWrapper.Hint.DEVICE, -1, d);
				item = sideTree.addSideItem(sideTree.devices_iter, d, dv, d.getDisplayName(), ViewWrapper.Hint.NONE);
				add_to_main_views (dv);
			}
		}
	}


	/**
	 * This is handled more carefully inside each ViewWrapper object.
	 */
	public void update_sensitivities() {
		if(!initialization_finished)
			return;

		debug ("UPDATE SENSITIVITIES");

		bool folder_set = (lm.music_folder_dir != "");
		bool have_media = lm.media_count() > 0;
		bool doing_ops = lm.doing_file_operations();
		bool media_active = lm.media_active;

		fileImportMusic.set_sensitive(!doing_ops && folder_set);
		fileRescanMusicFolder.set_sensitive(!doing_ops && folder_set);

		if(doing_ops) {
			topDisplay.show_progressbar();
		}
		else if(media_active && lm.media_info.media.mediatype == 3) {
			topDisplay.hide_scale_and_progressbar();
		}
		else {
			topDisplay.show_scale();
		}

		// HIDE SIDEBAR AND VIEWS WHEN PLAYING VIDEOS ...
		sourcesToMedias.set_visible(viewSelector.selected != 2);
		// Disabled due to a bug in GDK (version 3.4)
		//videoArea.set_no_show_all (viewSelector.selected != 2);
		videoArea.set_visible(viewSelector.selected == 2);

		bool show_top_display = media_active || doing_ops;
		topDisplay.set_visible (show_top_display);

		topDisplay.set_scale_sensitivity(media_active);

		if (music_library_view.current_view == ViewWrapper.ViewType.WELCOME) {
			music_library_view.welcome_screen.set_item_sensitivity(0, !doing_ops);
			foreach(int key in music_welcome_screen_keys.keys)
				music_library_view.welcome_screen.set_item_sensitivity(key, !doing_ops);
		}

		statusBar.set_visible(have_media);
		//infoPanel.set_visible(have_media);

		//bool show_info_panel = show_more && media_active;
		//infoPanel.set_visible(show_info_panel);
		
		//bool show_info_panel_chooser = showmain_views && mediaActive;
		//infoPanelChooser.set_visible(show_info_panel_chooser);

		// hide playlists when media list is empty
		sideTree.setVisibility(sideTree.playlists_iter, have_media);

		if(!lm.media_active || have_media && !lm.playing) {
			playButton.set_stock_id(Gtk.Stock.MEDIA_PLAY);
		}
	}

	public virtual void progressNotification(string? message, double progress) {
		if(message != null && progress >= 0.0 && progress <= 1.0)
			topDisplay.set_label_markup(message);

		topDisplay.set_progress_value(progress);
	}

	public void updateInfoLabel() {
		if(lm.doing_file_operations()) {
			debug ("doing file operations, returning null in updateInfoLabel\n");
			return;
		}

		if(!lm.media_active) {
			topDisplay.set_label_markup("");
			debug ("setting info label as ''\n");
			return;
		}

		string beg = "";

		if(lm.media_info.media.mediatype == 3) // radio
			beg = "<b>" + lm.media_info.media.album_artist.replace("\n", "") + "</b>\n";

		//set the title
		Media s = lm.media_info.media;
		var title = "<b>" + s.title.replace("&", "&amp;") + "</b>";
		var artist = ((s.artist != "" && s.artist != _("Unknown Artist")) ? (_(" by ") + "<b>" + s.artist.replace("&", "&amp;") + "</b>") : "");
		var album = ((s.album != "" && s.album != _("Unknown Album")) ? (_(" on ") + "<b>" + s.album.replace("&", "&amp;") + "</b>") : "");

		var media_label = beg + title + artist + album;
		topDisplay.set_label_markup(media_label);
	}

	/** This should be used whenever a call to play a new media is made
	 * @param s The media that is now playing
	 */
	public virtual void media_played(int i, int old) {
		/*if(old == -2 && i != -2) { // -2 is id reserved for previews
			Media s = settings.getLastMediaPlaying();
			s = lm.media_from_name(s.title, s.artist);

			if(s.rowid != 0) {
				lm.playMedia(s.rowid);
				int position = (int)settings.getLastMediaPosition();
				topDisplay.change_value(ScrollType.NONE, position);
			}

			return;
		}*/

		updateInfoLabel();

		//reset the media position
		topDisplay.set_scale_sensitivity(true);
		topDisplay.set_scale_range(0.0, lm.media_info.media.length);

		if(lm.media_from_id(i).mediatype == 1 || lm.media_from_id(i).mediatype == 2) {
			/*message("setting position to resume_pos which is %d\n", lm.media_from_id(i).resume_pos );
			Timeout.add(250, () => {
				topDisplay.change_value(ScrollType.NONE, lm.media_from_id(i).resume_pos);
				return false;
			});*/
		}
		else {
			topDisplay.change_value(ScrollType.NONE, 0);
		}

		//if(!mediaPosition.get_sensitive())
		//	mediaPosition.set_sensitive(true);

		//reset some booleans
		tested_for_video = false;
		queriedlastfm = false;
		media_considered_played = false;
		added_to_play_count = false;
		scrobbled_track = false;

		if(!lm.media_info.media.isPreview) {
			infoPanel.updateMedia(lm.media_info.media.rowid);
			if(settings.getMoreVisible())
				infoPanel.set_visible(true);

			// FIXME: Handle this in ViewWrapper.vala update_column_browser();
		}

		update_sensitivities();
#if HAVE_INTERNET_RADIO
		// if radio, we can't depend on current_position_update. do that stuff now.
		if(lm.media_info.media.mediatype == 3) {
			queriedlastfm = true;
			similarMedias.queryForSimilar(lm.media_info.media);

			try {
				Thread.create<void*>(lastfm_track_thread_function, false);
				Thread.create<void*>(lastfm_album_thread_function, false);
				Thread.create<void*>(lastfm_artist_thread_function, false);
				Thread.create<void*>(lastfm_update_nowplaying_thread_function, false);
			}
			catch(GLib.ThreadError err) {
				warning ("ERROR: Could not create last fm thread: %s \n", err.message);
			}

			// always show notifications for the radio, since user likely does not know media
			mkl.showNotification(lm.media_info.media.rowid);
		}
#endif
	}

	public virtual void playback_stopped(int was_playing) {
		//reset some booleans
		tested_for_video = false;
		queriedlastfm = false;
		media_considered_played = false;
		added_to_play_count = false;

		update_sensitivities();

		debug ("stopped\n");
	}

	public virtual void medias_updated(Collection<int> ids) {
		if(lm.media_active && ids.contains(lm.media_info.media.rowid)) {
			updateInfoLabel();
		}
	}

	public void* lastfm_track_thread_function () {
		LastFM.TrackInfo track = new LastFM.TrackInfo.basic();

		string artist_s = lm.media_info.media.artist;
		string track_s = lm.media_info.media.title;

		/* first fetch track info since that is most likely to change */
		if(!lm.track_info_exists(track_s + " by " + artist_s)) {
			track = new LastFM.TrackInfo.with_info(artist_s, track_s);

			if(track != null)
				lm.save_track(track);

			if(track_s == lm.media_info.media.title && artist_s == lm.media_info.media.artist)
				lm.media_info.track = track;
		}

		return null;
	}

	public void* lastfm_album_thread_function () {
		LastFM.AlbumInfo album = new LastFM.AlbumInfo.basic();

		string artist_s = lm.media_info.media.artist;
		string album_s = lm.media_info.media.album;

		/* fetch album info now. only save if still on current media */
		if(!lm.album_info_exists(album_s + " by " + artist_s) || lm.get_cover_album_art(lm.media_info.media.rowid) == null) {
			album = new LastFM.AlbumInfo.with_info(artist_s, album_s);

			if(album != null)
				lm.save_album(album);

			/* make sure we save image to right location (user hasn't changed medias) */
			if(lm.media_active && album != null && album_s == lm.media_info.media.album &&
			artist_s == lm.media_info.media.artist && lm.media_info.media.getAlbumArtPath().contains("media-audio.png")) {
				lm.media_info.album = album;

				if (album.url_image.url != null && lm.settings.getUpdateFolderHierarchy()) {
					lm.save_album_locally(lm.media_info.media.rowid, album.url_image.url);

					// start thread to load all the medias pixbuf's
					try {
						Thread.create<void*>(lm.fetch_thread_function, false);
					}
					catch(GLib.ThreadError err) {
						warning("Could not create thread to load media pixbuf's: %s \n", err.message);
					}
				}
			}
			else {
				return null;
			}
		}

		return null;
	}

	public void* lastfm_artist_thread_function () {
		LastFM.ArtistInfo artist = new LastFM.ArtistInfo.basic();

		string artist_s = lm.media_info.media.artist;

		/* fetch artist info now. save only if still on current media */
		if(!lm.artist_info_exists(artist_s)) {
			artist = new LastFM.ArtistInfo.with_artist(artist_s);

			if(artist != null)
				lm.save_artist(artist);

			//try to save artist art locally
			if(lm.media_active && artist != null && artist_s == lm.media_info.media.artist &&
			!File.new_for_path(lm.media_info.media.getArtistImagePath()).query_exists()) {
				lm.media_info.artist = artist;

			}
			else {
				return null;
			}
		}

		Idle.add( () => { infoPanel.updateCoverArt(true); return false;});

		return null;
	}

	public void* lastfm_update_nowplaying_thread_function() {
		if(lm.media_active) {
			lm.lfm.updateNowPlaying(lm.media_info.media.title, lm.media_info.media.artist);
		}

		return null;
	}

	public void* lastfm_scrobble_thread_function () {
		if(lm.media_active) {
			lm.lfm.scrobbleTrack(lm.media_info.media.title, lm.media_info.media.artist);
		}

		return null;
	}

	public bool updateMediaInfo() {
		infoPanel.updateMedia(lm.media_info.media.rowid);

		return false;
	}

	public virtual void previousClicked () {
		if(lm.player.getPosition() < 5000000000 || (lm.media_active && lm.media_info.media.mediatype == 3)) {
			int prev_id = lm.getPrevious(true);

			/* test to stop playback/reached end */
			if(prev_id == 0) {
				lm.player.pause();
				lm.playing = false;
				update_sensitivities();
				return;
			}
		}
		else
			topDisplay.change_value(ScrollType.NONE, 0);
	}

	public virtual void playClicked () {
		if(!lm.media_active) {
			debug("No media is currently playing. Starting from the top\n");
			//set current medias by current view
			Widget w = get_current_view_wrapper ();
			
			if(w is ViewWrapper) {
				((ViewWrapper)w).list_view.set_as_current_list(1, true);
			}
			else {
				w = sideTree.getWidget(sideTree.library_music_iter);
				((ViewWrapper)w).list_view.set_as_current_list(1, true);
			}

			lm.getNext(true);

			lm.playing = true;
			playButton.set_stock_id(Gtk.Stock.MEDIA_PAUSE);
			lm.player.play();
		}
		else {
			if(lm.playing) {
				lm.playing = false;
				lm.player.pause();

				playButton.set_stock_id(Gtk.Stock.MEDIA_PLAY);
			}
			else {
				lm.playing = true;
				lm.player.play();
				playButton.set_stock_id(Gtk.Stock.MEDIA_PAUSE);
			}
		}

		playPauseChanged();
	}

	public virtual void nextClicked() {
		// if not 90% done, skip it
		if(!added_to_play_count) {
			lm.media_info.media.skip_count++;

			// don't update, it will be updated eventually
			//lm.update_media(lm.media_info.media, false, false);
		}

		int next_id;
		if(lm.next_gapless_id != 0) {
			next_id = lm.next_gapless_id;
			lm.playMedia(lm.next_gapless_id, false);
		}
		else
			next_id = lm.getNext(true);

		/* test to stop playback/reached end */
		if(next_id == 0) {
			lm.player.pause();
			lm.playing = false;
			update_sensitivities();
			return;
		}
	}

	public virtual void loveButtonClicked() {
		lm.lfm.loveTrack(lm.media_info.media.title, lm.media_info.media.artist);
	}

	public virtual void banButtonClicked() {
		lm.lfm.banTrack(lm.media_info.media.title, lm.media_info.media.artist);
	}

	public virtual void searchFieldIconPressed(EntryIconPosition p0, Gdk.Event p1) {
		Widget w = get_current_view_wrapper ();
		w.focus(DirectionType.UP);
	}

	public virtual void on_quit() {
		lm.settings.setLastMediaPosition((int)((double)lm.player.getPosition()/1000000000));
		if(lm.media_active) {
			lm.media_info.media.resume_pos = (int)((double)lm.player.getPosition()/1000000000);
			lm.update_media(lm.media_info.media, false, false);
		}
		lm.player.pause();

		// Terminate Libnotify
		Notify.uninit ();
		
		// Search
		settings.setSearchString (searchField.get_text());
		
		// Save info pane (context pane) width
		settings.setMoreWidth(infoPanel.get_allocated_width());
		
		// Save sidebar width
		settings.setSidebarWidth(sourcesToMedias.position);
	}


	public virtual void fileImportMusicClick() {
		if(!lm.doing_file_operations()) {
			/*if(!(GLib.File.new_for_path(lm.settings.getMusicFolder()).query_exists() && lm.settings.getCopyImportedMusic())) {
				var dialog = new MessageDialog(this, DialogFlags.DESTROY_WITH_PARENT, MessageType.ERROR, ButtonsType.OK,
				"Before importing, you must mount your music folder.");

				var result = dialog.run();
				dialog.destroy();

				return;
			}*/

			string folders_list = "";
			string[] folders = {};
			var _folders = new SList<string> ();
			var file_chooser = new FileChooserDialog (_("Import Music"), this,
									  FileChooserAction.SELECT_FOLDER,
									  Gtk.Stock.CANCEL, ResponseType.CANCEL,
									  Gtk.Stock.OPEN, ResponseType.ACCEPT);
			file_chooser.set_select_multiple (true);
			file_chooser.set_local_only(true);

			if (file_chooser.run () == ResponseType.ACCEPT) {
				_folders = file_chooser.get_filenames();
			}
			file_chooser.destroy ();
			
			for (int i=0;i< (int)(_folders.length ());i++) {
                folders += _folders.nth_data (i);
            }

            for (int i=0;i<folders.length;i++) {
			    if(folders[i] == "" || folders[i] != settings.getMusicFolder()) {
			        folders_list += folders[i];
			        if (i + 1 != folders.length)
			            folders_list += ", ";
			    }
			}
			if(GLib.File.new_for_path(lm.settings.getMusicFolder()).query_exists()) {
				topDisplay.set_label_markup(_("<b>Importing</b> music from <b>%s</b> to library.").printf(folders_list));
				topDisplay.show_progressbar();

				lm.add_folder_to_library(folders[0], folders[1:folders.length]);
				update_sensitivities();
			}
		}
		else {
			debug("Can't add to library.. already doing file operations\n");
		}
	}

	public virtual void fileRescanMusicFolderClick() {
		if(!lm.doing_file_operations()) {
			if(GLib.File.new_for_path(this.settings.getMusicFolder()).query_exists()) {
				topDisplay.set_label_markup("<b>" + _("Rescanning music folder for changes") + "</b>");
				topDisplay.show_progressbar();

				lm.rescan_music_folder();
				update_sensitivities();
			}
			else {
				doAlert(_("Could not find Music Folder"), _("Please make sure that your music folder is accessible and mounted."));
			}
		}
		else {
			debug("Can't rescan.. doing file operations already\n");
		}
	}

	public void resetSideTree(bool clear_views) {
		sideTree.resetView();

		// clear all other playlists, reset to Music, populate music
		if(clear_views) {
			message("clearing all views...\n");
			main_views.get_children().foreach( (w) => {
				if(w is ViewWrapper && !(w is DeviceViewWrapper)) {
					ViewWrapper vw = (ViewWrapper)w;
					debug("doing clear\n");
					//vw.do_update(vw.current_view, new LinkedList<int>(), true, true, false);
					vw.set_media(new LinkedList<int>());
					debug("cleared\n");
				}
			});
			message("all cleared\n");
		}
		else {
			ViewWrapper vw = (ViewWrapper)sideTree.getWidget(sideTree.library_music_iter);
			//vw.do_update(vw.current_view, lm.song_ids(), true, true, false);
			//vw.column_browser.populate (lm.song_ids());
			vw.set_media(lm.song_ids());

#if HAVE_PODCASTS
			vw = (ViewWrapper)sideTree.getWidget(sideTree.library_podcasts_iter);
			//vw.do_update(vw.current_view, lm.podcast_ids(), true, true, false);
			vw.set_media(lm.podcast_ids());
#endif

#if HAVE_INTERNET_RADIO
			vw = (ViewWrapper)sideTree.getWidget(sideTree.network_radio_iter);
			//vw.do_update(vw.current_view, lm.station_ids(), true, true, false);
			vw.set_media(lm.station_ids());
#endif
		}
	}

	public virtual void musicCounted(int count) {
		debug ("found %d media, importing.\n", count);
	}

	/* this is after setting the music library */
	public virtual void musicAdded(LinkedList<string> not_imported) {

		if(lm.media_active) {
			updateInfoLabel();
		}
		else
			topDisplay.set_label_text("");

		//resetSideTree(false);
		//var init = searchField.get_text();
		//searchField.set_text("up");

		if(not_imported.size > 0) {
			NotImportedWindow nim = new NotImportedWindow(this, not_imported, lm.settings.getMusicFolder());
			nim.show();
		}

		update_sensitivities();

		//now notify user
		try {
			if (Notify.is_initted ()) {
				notification.close();
				notification.update(_("Import Complete"), _("Noise has imported your library."), "beatbox");
				notification.set_image_from_pixbuf(Icons.BEATBOX.render (Gtk.IconSize.DIALOG));
				notification.set_timeout (Notify.EXPIRES_DEFAULT);
				notification.set_urgency (Notify.Urgency.NORMAL);
				notification.show();
			}
		}
		catch(GLib.Error err) {
			stderr.printf("Could not show notification: %s\n", err.message);
		}
	}

	/* this is when you import music from a foreign location into the library */
	public virtual void musicImported(LinkedList<Media> new_medias, LinkedList<string> not_imported) {
		if(lm.media_active) {
			updateInfoLabel();
		}
		else
			topDisplay.set_label_text("");

		resetSideTree(false);
		//searchField.changed();

		update_sensitivities();
	}

	public virtual void musicRescanned(LinkedList<Media> new_medias, LinkedList<string> not_imported) {
		if(lm.media_active) {
			updateInfoLabel();
		}
		else
			topDisplay.set_label_text("");

		resetSideTree(false);
		debug("music Rescanned\n");
		update_sensitivities();
	}

	public void editPreferencesClick() {
		PreferencesWindow pw = new PreferencesWindow(lm, this);

		pw.changed.connect( (folder) => {
			setMusicFolder(folder);
		});
	}

	public void setMusicFolder(string folder) {
		if(lm.doing_file_operations())
			return;

		if(lm.song_ids().size > 0 || lm.playlist_count() > 0) {
			var smfc = new SetMusicFolderConfirmation(lm, this, folder);
			smfc.finished.connect( (cont) => {
				if(cont) {
					lm.set_music_folder(folder);
				}
			});
		}
		else {
			lm.set_music_folder(folder);
		}
	}

	public virtual void end_of_stream() {
		nextClicked();
	}

	public virtual void current_position_update(int64 position) {
		if (!lm.media_active)
			return;

		if (lm.media_info.media.rowid == Media.PREVIEW_ROWID) // is preview
			return;

		double sec = ((double)position/1000000000);

		if(lm.player.set_resume_pos)
			lm.media_info.media.resume_pos = (int)sec;

		// at about 3 seconds, update last fm. we wait to avoid excessive querying last.fm for info
		if(position > 3000000000 && !queriedlastfm) {
			queriedlastfm = true;

			ViewWrapper vw = (ViewWrapper)sideTree.getWidget(sideTree.playlists_similar_iter);
			if(vw.has_list_view && !(vw.list_view as BaseListView).is_current_view) {
				vw.show_retrieving_similars();
				similarMedias.queryForSimilar(lm.media_info.media);
			}

			try {
				Thread.create<void*>(lastfm_track_thread_function, false);
				Thread.create<void*>(lastfm_album_thread_function, false);
				Thread.create<void*>(lastfm_artist_thread_function, false);
				Thread.create<void*>(lastfm_update_nowplaying_thread_function, false);
			}
			catch(GLib.ThreadError err) {
				warning("ERROR: Could not create last fm thread: %s \n", err.message);
			}
		}

		//at 30 seconds in, we consider the media as played
		if(position > 30000000000 && !media_considered_played) {
			media_considered_played = true;
			lm.media_info.media.last_played = (int)time_t();

#if HAVE_PODCASTS
			if(lm.media_info.media.mediatype == 1) { //podcast
				added_to_play_count = true;
				++lm.media_info.media.play_count;
			}
#endif

			lm.update_media(lm.media_info.media, false, false);

			// add to the already played list
			lm.add_already_played(lm.media_info.media.rowid);
			sideTree.updateAlreadyPlayed();

#if HAVE_ZEITGEIST
			var event = new Zeitgeist.Event.full (Zeitgeist.ZG_ACCESS_EVENT,
			                                       Zeitgeist.ZG_SCHEDULED_ACTIVITY, "app://beatbox.desktop",
			                                       new Zeitgeist.Subject.full(lm.media_info.media.uri,
			                                                                   Zeitgeist.NFO_AUDIO,
			                                                                   Zeitgeist.NFO_FILE_DATA_OBJECT,
			                                                                   "text/plain", "",
			                                                                   lm.media_info.media.title, ""));
			new Zeitgeist.Log ().insert_events_no_reply(event);
#endif
		}

		// at halfway, scrobble
		if((double)(sec/(double)lm.media_info.media.length) > 0.50 && !scrobbled_track) {
			scrobbled_track = true;
			try {
				Thread.create<void*>(lastfm_scrobble_thread_function, false);
			}
			catch(GLib.ThreadError err) {
				warning("ERROR: Could not create last fm thread: %s \n", err.message);
			}
		}

		// at 80% done with media, add 1 to play count
		if((double)(sec/(double)lm.media_info.media.length) > 0.80 && !added_to_play_count) {
			added_to_play_count = true;
			lm.media_info.media.play_count++;
			lm.update_media(lm.media_info.media, false, false);
		}
	}

	public void media_not_found(int id) {
		var not_found = new FileNotFoundDialog(lm, this, id);
		not_found.show();
	}

	public virtual void similarRetrieved(LinkedList<int> similarIDs, LinkedList<Media> similarDont) {
		Widget w = sideTree.getWidget(sideTree.playlists_similar_iter);

		((ViewWrapper)w).similarsFetched = true;
		((ViewWrapper)w).set_media (similarIDs);

		infoPanel.updateMediaList(similarDont);
	}

	public void set_statusbar_info (ViewWrapper.Hint media_type, uint total_medias,
									 uint total_mbs, uint total_seconds)
	{
		statusBar.set_total_medias (total_medias, media_type);
		statusBar.set_files_size (total_mbs);
		statusBar.set_total_time (total_seconds);
	}

	public void music_welcome_screen_activated(int index) {
		if(index == 0) {
			if(!lm.doing_file_operations()) {
				string folder = "";
				var file_chooser = new FileChooserDialog (_("Choose Music Folder"), this,
										  FileChooserAction.SELECT_FOLDER,
										  Gtk.Stock.CANCEL, ResponseType.CANCEL,
										  Gtk.Stock.OPEN, ResponseType.ACCEPT);
				file_chooser.set_local_only(true);
				if (file_chooser.run () == ResponseType.ACCEPT) {
					folder = file_chooser.get_filename();
				}
				file_chooser.destroy ();

				if(folder != "" && (folder != settings.getMusicFolder() || lm.media_count() == 0)) {
					setMusicFolder(folder);
				}
			}
		}
		else {
			if(lm.doing_file_operations())
				return;

			Device d = music_welcome_screen_keys.get(index);

			if(d.getContentType() == "cdrom") {
				sideTree.expandItem(sideTree.convertToFilter(sideTree.devices_iter), true);
				sideTree.setSelectedIter(sideTree.convertToFilter(sideTree.devices_cdrom_iter));
				sideTree.sideListSelectionChange();

				var to_transfer = new LinkedList<int>();
				foreach(int i in d.get_medias())
					to_transfer.add(i);

				d.transfer_to_library(to_transfer);
			}
			else {
				// ask the user if they want to import medias from device that they don't have in their library (if any)
				if(lm.settings.getMusicFolder() != "") {
					var externals = new LinkedList<int>();
					foreach(var i in d.get_medias()) {
						if(lm.media_from_id(i).isTemporary)
							externals.add(i);
					}

					TransferFromDeviceDialog tfdd = new TransferFromDeviceDialog(this, d, externals);
					tfdd.show();
				}
			}
		}
	}

	public virtual void repeatChooserOptionChanged(int val) {
		lm.settings.setRepeatMode(val);

		if(val == 0)
			lm.repeat = LibraryManager.Repeat.OFF;
		else if(val == 1)
			lm.repeat = LibraryManager.Repeat.MEDIA;
		else if(val == 2)
			lm.repeat = LibraryManager.Repeat.ALBUM;
		else if(val == 3)
			lm.repeat = LibraryManager.Repeat.ARTIST;
		else if(val == 4)
			lm.repeat = LibraryManager.Repeat.ALL;
	}

	public virtual void shuffleChooserOptionChanged(int val) {
		if(val == 0)
			lm.setShuffleMode(LibraryManager.Shuffle.OFF, true);
		else if(val == 1)
			lm.setShuffleMode(LibraryManager.Shuffle.ALL, true);
	}

	public virtual bool addPlaylistChooserOptionClicked(Gdk.EventButton event) {
		if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 1) {
			sideTree.playlistMenuNewClicked();
			return true;
		}

		return false;
	}


	private Gtk.Window? equalizer_window = null;

	public virtual void eq_option_chooser_clicked(int val) {
	/*
		if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 1) {
			if (equalizer_window != null) {
				equalizer_window.destroy();
				equalizer_window = null;
			}
			else {
				equalizer_window = new EqualizerWindow(lm, this);
				equalizer_window.show_all ();
			}
			return true;
		}
	*/

		if (equalizer_window == null && val == 1) {
			equalizer_window = new EqualizerWindow(lm, this);
			equalizer_window.show_all ();
		}
		else if (val == 0) {
			equalizer_window.destroy();
			equalizer_window = null;
		}

		//return false;
	}


	public virtual void infoPanelChooserOptionChanged(int val) {
		infoPanel.set_visible(val == 1);
		lm.settings.setMoreVisible(val == 1);
	}

	public Widget? get_current_view_wrapper () {
		return main_views.get_nth_page (main_views.get_current_page());
	}

	public void searchFieldActivate() {
		Widget w = get_current_view_wrapper ();

		if(w is ViewWrapper) {
			ViewWrapper vw = (ViewWrapper)w;

			if (((ViewWrapper)w).has_list_view)
				vw.list_view.set_as_current_list(1, !(vw.list_view as BaseListView).is_current_view);

			lm.current_index = 0;
			lm.playMedia(lm.mediaFromCurrentIndex(0), false);

			if(!lm.playing)
				playClicked();
		}
	}

	public virtual void dragReceived(Gdk.DragContext context, int x, int y, Gtk.SelectionData data, uint info, uint timestamp) {
		if(dragging_from_music)
			return;

		var files_dragged = new LinkedList<string>();
		debug("dragged\n");
		foreach (string uri in data.get_uris ()) {
			files_dragged.add(File.new_for_uri(uri).get_path());
		}

		lm.add_files_to_library(files_dragged);
	}

	public void doAlert(string title, string message) {
		var dialog = new MessageDialog(this, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK,
				title);

		dialog.title = "Noise";
		dialog.secondary_text = message;
		dialog.secondary_use_markup = true;

		dialog.run();
		dialog.destroy();
	}

	/* device stuff for welcome screen */
	public void device_added(Device d) {
		// add option to import in welcome screen
		string secondary = (d.getContentType() == "cdrom") ? _("Import songs from audio CD") : _("Import media from device");
		int key = music_library_view.welcome_screen.append_with_image( new Image.from_gicon(d.get_icon(), Gtk.IconSize.DIALOG), d.getDisplayName(), secondary);
		music_welcome_screen_keys.set(key, d);
	}

	public void device_removed(Device d) {
		// remove option to import from welcome screen
		int key = 0;
		foreach(int i in music_welcome_screen_keys.keys) {
			if(music_welcome_screen_keys.get(i) == d) {
				key = i;
				break;
			}
		}

		if(key != 0) {
			music_welcome_screen_keys.unset(key);
			music_library_view.welcome_screen.remove_item(key);
		}
	}
}
