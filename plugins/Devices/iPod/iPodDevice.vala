/*-
 * Copyright (c) 2011-2012       Corentin Noël <tintou@mailoo.org>
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

using GPod;
using Gee;

public class Noise.Plugins.iPodDevice : GLib.Object, Noise.Device {
    Noise.LibraryManager lm;
    Noise.DevicePreferences pref;
    iTunesDB db;
    Mount mount;
    GLib.Icon icon;
    bool currently_syncing = false;
    bool currently_transferring = false;
    bool sync_cancelled = false;
    bool transfer_cancelled = false;
    int index = 0;
    int total = 0;
    string current_operation = "";
    
    HashMap<unowned GPod.Track, Noise.Media> medias;
    HashMap<unowned GPod.Track, Noise.Media> songs;
    HashMap<unowned GPod.Track, Noise.Media> podcasts;
    HashMap<unowned GPod.Track, Noise.Media> audiobooks;
    HashMap<unowned GPod.Playlist, Noise.StaticPlaylist> playlists;
    HashMap<unowned GPod.Playlist, Noise.SmartPlaylist> smart_playlists;
    
    public iPodDevice(Noise.LibraryManager lm, Mount mount) {
        this.lm = lm;
        this.mount = mount;
        
        pref = lm.device_manager.get_device_preferences(get_unique_identifier());
        if(pref == null) {
            pref = new Noise.DevicePreferences(get_unique_identifier());
            lm.device_manager.add_device_preferences(pref);
        }
        
        icon = new Icon (isNew () ? "phone" : "multimedia-player").gicon;
        
        medias = new HashMap<unowned GPod.Track, Noise.Media>();
        songs = new HashMap<unowned GPod.Track, Noise.Media>();
        podcasts = new HashMap<unowned GPod.Track, Noise.Media>();
        audiobooks = new HashMap<unowned GPod.Track, Noise.Media>();
        playlists = new HashMap<unowned GPod.Playlist, Noise.StaticPlaylist>();
        smart_playlists = new HashMap<unowned GPod.Playlist, Noise.SmartPlaylist>();
    }
    
    public Noise.DevicePreferences get_preferences() {
        return pref;
    }
    
    public bool start_initialization() {
        try {
            db = iTunesDB.parse(mount.get_default_location().get_path());
        }
        catch(Error err) {
            critical("Error parsing db at %s: %s\n", get_uri(), err.message);
            return false;
        }
        
        return true;
    }
    
    public void finish_initialization() {
        device_unmounted.connect( () => {
            
        });
        
        finish_initialization_thread ();
    }
    
    async void finish_initialization_thread() {
    
        Threads.add (() => {
            // get all songs first
            for(int i = 0; i < db.tracks.length(); ++i) {
                unowned GPod.Track t = db.tracks.nth_data(i);
                //message("found track and rating is %d and app rating %d and id is %d\n", (int)db.tracks.nth_data(i).rating, (int)db.tracks.nth_data(i).app_rating, (int)db.tracks.nth_data(i).id);
                var m = iPodMediaHelper.media_from_track (get_uri(), t);
                if (m.file_exists && !this.medias.has(t, m)) {
                    if(t.mediatype == GPod.MediaType.AUDIO) {
                        this.songs.set(t, m);
                        this.medias.set(t, m);
                    } else if(t.mediatype == GPod.MediaType.PODCAST || t.mediatype == 0x00000006) { // 0x00000006 = video podcast
                        this.podcasts.set(t, m);
                        this.medias.set(t, m);
                    } else if(t.mediatype == GPod.MediaType.AUDIOBOOK || t.mediatype == 12) {
                        this.audiobooks.set(t, m);
                        this.medias.set(t, m);
                    } else if(t.mediatype == GPod.MediaType.MUSICVIDEO) {
                        warning("musicvideo");
                    } else if(t.mediatype == GPod.MediaType.TVSHOW) {
                        warning("tvshow");
                    } else if(t.mediatype == GPod.MediaType.RINGTONE) {
                        warning("ringtone");
                    } else if(t.mediatype == GPod.MediaType.RENTAL) {
                        warning("rental");
                    } else if(t.mediatype == GPod.MediaType.ITUNES_EXTRA) {
                        warning("itunes_extra");
                    } else if(t.mediatype == GPod.MediaType.MEMO) {
                        warning("memo");
                    } else if(t.mediatype == GPod.MediaType.ITUNES_U) {
                        warning("itunes_u");
                    } else if(t.mediatype == GPod.MediaType.EPUB_BOOK) {
                        warning("epub");
                    } else {
                        warning ("%u", t.mediatype);
                    }
                }
            }
            sync_finished (true);
            
            
            //lock(lm._medias) {
                //lm.add_medias(trToSo, false);
            //}
            
            // TODO: create support for playlists
            /*foreach (unowned GPod.Playlist p in db.playlists) {
                
                if(!p.is_spl) {
                    Playlist bbPlaylist = Playlist.from_ipod(p);
                    
                    foreach(unowned GPod.Track t in medias.keys) {
                        if(p.contains_track(t)) {
                            bbPlaylist.addMedia(medias.get(t));
                        }
                    }
                    
                    lm.add_playlist(bbPlaylist);
                    playlists.set(p, bbPlaylist.rowid);
                }
                else {
                    Noise.SmartPlaylist sp = Noise.SmartPlaylist.from_ipod(p);
                    
                    
                }
            }*/

            Idle.add( () => {
                initialized(this);
                
                return false;
            });
        });

        yield;
    }
    
    public bool isNew() {
        return mount.get_default_location().get_parse_name().has_prefix("afc://");
    }
    
    public string getEmptyDeviceTitle() {
        return _("Empty device!");
    }
    
    public string getEmptyDeviceDescription() {
        return _("This device does not contain any music.");
    }
    
    public string getContentType() {
        //TODO: define global constants!
        if(isNew())
            return "ipod-new";
        else
            return "ipod-old";
    }
    
    public string getDisplayName() {
        return db.playlist_mpl().name;
    }
    
    public void setDisplayName(string name) {
        db.playlist_mpl().name = name;
        try {
            mount.get_default_location().set_display_name(name);
        }
        catch(GLib.Error err) {
            critical("Could not set iPod Mount Display Name: %s\n", err.message);
        }
        lm.device_name_changed (this);
    }
    
    public string get_fancy_description() {
        /*unowned GPod.iPodInfo ipod_info = db.device.get_ipod_info();
        critical("got here\n");
        GPod.iPodModel enum_model = ipod_info.ipod_model;
        GPod.iPodGeneration enum_gen = ipod_info.ipod_generation;*/
        message("got here\n");
        string model = "model here";//GPod.iPodInfo.get_ipod_model_name_string(enum_model);
        message("got here\n");
        //var gen = GPod.iPodInfo.get_ipod_generation_string(enum_gen);
        string gen = "gen 1";
        return gen + " " + model;
    }
    
    public void set_mount(Mount mount) {
        this.mount = mount;
    }
    
    public Mount get_mount() {
        return mount;
    }
    
    public string get_uri() {
        return mount.get_default_location().get_uri();
    }
    
    public void set_icon(GLib.Icon icon) {
        this.icon = icon;
    }
    
    public GLib.Icon get_icon() {
        return icon;
    }
    
    public uint64 get_capacity() {
        uint64 rv = 0;
        
        try {
            var file_info = File.new_for_uri(get_uri()).query_filesystem_info("filesystem::*", null);
            rv = file_info.get_attribute_uint64(GLib.FileAttribute.FILESYSTEM_SIZE);
        }
        catch(Error err) {
            critical("Error calculating capacity of iPod: %s\n", err.message);
        }
        
        return rv;
    }
    
    public string get_fancy_capacity() {
        return GLib.format_size (get_capacity());
    }
    
    public uint64 get_used_space() {
        return get_capacity() - get_free_space();
    }
    
    public uint64 get_free_space() {
        uint64 rv = 0;
        
        try {
            var file_info = File.new_for_uri(get_uri()).query_filesystem_info("filesystem::*", null);
            rv = file_info.get_attribute_uint64(GLib.FileAttribute.FILESYSTEM_FREE);
        }
        catch(Error err) {
            critical("Error calculating free space on iPod: %s\n", err.message);
        }
        
        return rv;
    }
    
    public void unmount() {
        mount.unmount_with_operation (GLib.MountUnmountFlags.NONE, null);
    }
    
    public void eject() {
        if (mount.can_eject ()) {
            mount.get_volume ().get_drive ().eject_with_operation (GLib.MountUnmountFlags.NONE, null);
        }
    }
    
    public bool has_custom_view() {
        return false;
    }
    
    public Gtk.Grid get_custom_view() {
        return new Gtk.Grid();
    }
    
    public bool read_only() {
        return false;
    }
    
    public bool supports_podcasts() {
        return db.device.supports_podcast();
    }
    
    public bool supports_audiobooks() {
        return true; // no device.supports_audiobook(), but there is audiobook playlist
    }
    
    public Collection<Noise.Media> get_medias() {
        return medias.values;
    }
    
    public Collection<Noise.Media> get_songs() {
        return songs.values;
    }
    
    public Collection<Noise.Media> get_podcasts() {
        return podcasts.values;
    }
    
    public Collection<Noise.Media> get_audiobooks() {
        return audiobooks.values;
    }
    
    public Collection<Noise.StaticPlaylist> get_playlists() {
        return playlists.values;
    }
    
    public Collection<Noise.SmartPlaylist> get_smart_playlists() {
        return smart_playlists.values;
    }
    
    public bool sync_medias() {
        if(currently_syncing) {
            warning("Tried to sync when already syncing\n");
            return false;
        }
        else if(lm.doing_file_operations()) {
            warning("Can't sync. Already doing file operations\n");
            return false;
        }
        
        if (lm.start_file_operations (_("Syncing <b>%s</b>...").printf (getDisplayName ()))) {
            current_operation = _("Syncing <b>%s</b>...").printf (getDisplayName ());
            lm.lw.update_sensitivities();
            
            currently_syncing = true;
            index = 0;
            total = 100;
            Timeout.add(500, doProgressNotificationWithTimeout);
            
            sync_medias_thread ();
        }
        return true;
    }
    
    public bool is_syncing() {
        return currently_syncing;
    }
    
    public bool is_transferring() {
        return currently_transferring;
    }
    
    public void cancel_sync() {
        sync_cancelled = true;
    }
    
    public void cancel_transfer() {
        transfer_cancelled = true;
    }
    
    public bool will_fit(LinkedList<Noise.Media> list) {
        uint64 list_size = 0;
        foreach(var m in list) {
            list_size += m.file_size;
        }
        
        return get_capacity() > list_size;
    }
    
    private bool will_fit_without(LinkedList<Noise.Media> list, LinkedList<Noise.Media> without) {
        uint64 list_size = 0;
        uint64 without_size = 0;
        foreach(var m in list) {
            list_size += m.file_size;
        }
        foreach(var m in without) {
            without_size += m.file_size;
        }
        if (without_size > list_size) {
            return true;
        } else {
            return get_capacity() > (list_size - without_size);
        }
    }
    
    private async void sync_medias_thread () {
        
        Threads.add (() => {
            bool error_occurred = false;
            int sub_index = 0;
            
            message("Found %d medias to sync.", list_to_sync ().size);
            Gee.LinkedList<Noise.Media> medias_to_remove = delete_doubles (songs.values, list_to_sync ());
            message("Found %d medias to remove.", medias_to_remove.size);
            Gee.LinkedList<Noise.Media> medias_to_sync = delete_doubles (list_to_sync (), songs.values);
            message("Found %d medias to add.", medias_to_sync.size);
            int total_medias = medias_to_remove.size + medias_to_sync.size;
            
            if (total_medias > 0) {
                if (will_fit_without(medias_to_sync, medias_to_remove)) {
                    db.start_sync();
                    foreach(var m in medias_to_remove) {
                        if(!sync_cancelled) {
                            foreach(var e in medias.entries) {
                                if(e.value == m) {
                                    remove_media (e.key);
                                    break;
                                }
                            }
                        }
                        ++sub_index;
                        index = (int)(85.0 * (double)((double)sub_index/(double)total_medias));
                    }
                    sub_index = 0;
                    foreach(var m in medias_to_sync) {
                        if(!sync_cancelled) {
                            add_media(m);
                        }
                        ++sub_index;
                        index = (int)(85.0 * ((double)sub_index/(double)total_medias));
                    }
                            
                    if(!sync_cancelled) {
                        // sync playlists
                        index = 90;
                        /* TODO: add support for podcasts & playlists
                        if (pref.sync_all_music == true) {
                            sync_playlists();
                        }
                        if (pref.sync_all_podcasts == true) {
                            sync_podcasts();
                        }*/
                        
                        current_operation = _("Finishing sync process...");
                        
                        try {
                            db.write();
                        }
                        catch(GLib.Error err) {
                            error_occurred = true;
                            sync_cancelled = true;
                        }
                        
                        index = 98;
                        
                        /// Clean up unused files
                        message ("Cleaning up iPod File System\n");
                        var music_folder = File.new_for_uri(get_uri () + GPod.Device.get_music_dir(mount.get_default_location().get_path()).replace (mount.get_default_location().get_path(), ""));
                        var used_paths = new LinkedList<string>();
                        foreach(unowned GPod.Track t in medias.keys) {
                            used_paths.add(get_uri() + GPod.iTunesDB.filename_ipod2fs(t.ipod_path));
                        }
                        index = 99;
                        cleanup_files(music_folder, used_paths);
                        index = 101;
                        
                        db.stop_sync();
                    } else {
                        current_operation = _("Cancelling Sync...");
                        try {
                            db.write();
                        } catch(Error err) {
                            critical("Error when writing iPod database. iPod contents may be incorrect: %s\n", err.message);
                        }
                        db.stop_sync();
                        index = total + 1;
                    }
                } else {
                        infobar_message (_("There is not enough space on Device to complete the Sync..."), Gtk.MessageType.INFO);
                        current_operation = _("There is not enough space on Device to complete the Sync...");
                }
            }

            Idle.add( () => {
                index = total + 1;
                pref.last_sync_time = (int)time_t();
                currently_syncing = false;
                
                sync_finished(!sync_cancelled);
                lm.finish_file_operations();
                lm.lw.update_sensitivities();
                sync_cancelled = false;
                
                return false;
            });
        });

        yield;
    }
    
    public Gee.LinkedList<Noise.Media> list_to_sync () {
        var medias_to_sync = new Gee.LinkedList<Noise.Media> ();
        if (pref.sync_music == true) {
            if (pref.sync_all_music == true) {
                foreach (Media m in lm.media ()) {
                    if (m != null)
                        medias_to_sync.add (m);
                }
            } else {
                foreach (Media m in lm.playlist_from_name (pref.music_playlist).medias) {
                    if (m != null)
                        medias_to_sync.add (m);
                }
            }
        }
        return medias_to_sync;
    }
    
    public Gee.LinkedList<Noise.Media> delete_doubles (Gee.Collection<Noise.Media> source_list, Gee.Collection<Noise.Media> to_remove) {
        var new_list = new Gee.LinkedList<Noise.Media> ();
        if (to_remove != null) {
            foreach(var m in source_list) {
                if (m != null) {
                    bool needed = true;
                    foreach(var med in to_remove) {
                        if (med != null && med.title != null) {
                            if (med.album != null && m.album != null) { // If you don't have the album name, don't care of it
                                if(med.title.down() == m.title.down() && med.artist.down() == m.artist.down() && med.album.down() == m.album.down()) {
                                    needed = false;
                                    break;
                                }
                            } else {
                                if(med.title.down() == m.title.down() && med.artist.down() == m.artist.down()) {
                                    needed = false;
                                    break;
                                }
                            }
                        }
                    }
                    if (needed == true)
                        new_list.add (m);
                }
            }
        } else {
            
            foreach(var m in source_list) {
                new_list.add (m);
            }
            
        }
        return new_list;
        
    }
    
    /**********************************
     * Specifically only adding medias. This is different and not a part
     * of sync. This is usually called on drag and drop to iPod.
     *********************************/
    bool add_medias(LinkedList<Noise.Media> list) {
        if(currently_syncing) {
            warning("Tried to add when already syncing\n");
            return false;
        }
        else if(lm.doing_file_operations()) {
            warning("Can't add. Already doing file operations\n");
            return false;
        }
        
        // Check if all current media + this list will fit.
        var new_list = new LinkedList<Noise.Media>();
        foreach(var m in list)
            new_list.add(m);
        foreach(var m in medias.values)
            new_list.add(m);
        bool fits = will_fit(new_list);
        if(!fits) {
            warning("Tried to sync medias that will not fit\n");
            return false;
        }
        
        if (lm.start_file_operations(_("Syncing <b>%s</b>...").printf (getDisplayName ()))) {
            current_operation = _("Syncing <b>%s</b>...").printf (getDisplayName ());
            lm.lw.update_sensitivities();
            
            currently_syncing = true;
            index = 0;
            total = list.size + 2;
            Timeout.add(500, doProgressNotificationWithTimeout);
            add_medias_thread (list);
        }
        
        return true;
    }
    
    async void add_medias_thread(LinkedList<Noise.Media> to_add) {
        
        Threads.add (() => {
            bool error_occurred = false;
            db.start_sync();
            
            ++index;
            
            // Actually add new items
            foreach(var m in to_add) {
                if(!sync_cancelled) {
                    add_media(m);
                    ++index;
                }
            }
            
            if(!sync_cancelled) {
                current_operation = _("Finishing sync process...");
                
                ++index;
                
                try {
                    db.write();
                }
                catch(GLib.Error err) {
                    critical("Error when writing iPod database. iPod contents may be incorrect: %s\n", err.message);
                    error_occurred = true;
                    sync_cancelled = true;
                }
                
                index = total + 1;
                
                db.stop_sync();
            }
            else {
                current_operation = _("Cancelling Sync...");
                
                try {
                    db.write();
                }
                catch(Error err) {
                    critical("Error when writing iPod database. iPod contents may be incorrect: %s\n", err.message);
                }
                
                db.stop_sync();
                index = total + 1;
            }

            Idle.add( () => {
                currently_syncing = false;
                
                sync_finished(!sync_cancelled);
                lm.finish_file_operations();
                lm.lw.update_sensitivities();
                sync_cancelled = false;
                
                return false;
            });
        });

        yield;
    }
    
    /* Adds to track list, mpl, and copies the file over */
    void add_media(Noise.Media s) {
        if(s == null)
            return;
        
        GPod.Track t = iPodMediaHelper.track_from_media (s);
        var pix = Noise.CoverartCache.instance.get_original_cover (s);
        if (pix != null)
            t.set_thumbnails_from_pixbuf (pix);

        current_operation = _("Adding <b>$NAME</b> by <b>$ARTIST</b> to $DEVICE");
        current_operation = current_operation.replace ("$NAME", t.title ?? "");
        current_operation = current_operation.replace ("$ARTIST", t.artist ?? "");
        current_operation = current_operation.replace ("$DEVICE", getDisplayName() ?? "");
        debug ("Adding media %s by %s\n", t.title, t.artist);
        db.track_add((owned)t, -1);
        
        unowned GPod.Track added = db.tracks.nth_data(db.tracks.length() - 1);
        
        if(added == null || added.title != s.title) {
            warning("Track was not properly appended. Returning.\n");
            return;
        }
        
        unowned GPod.Playlist mpl = db.playlist_mpl();
        mpl.add_track(added, -1);
        
        if(added.mediatype == GPod.MediaType.PODCAST) {
            unowned GPod.Playlist ppl = db.playlist_podcasts();
            ppl.add_track(added, -1);
        }
        /*else if(added.mediatype == GPod.MediaType.AUDIOBOOK) {
            unowned GPod.Playlist apl = db.playlist_audiobooks();
            apl.add_track(added, -1);
        }*/
        
        bool success = false;
        try {
            success = db.cp_track_to_ipod(added, File.new_for_uri(s.uri).get_path());
            debug("Copied media %s to ipod\n", added.title);
        } catch(Error err) {
            warning("Error adding/copying song %s to iPod: %s\n", s.title, err.message);
        }
        
        if(success) {
            Noise.Media on_ipod = iPodMediaHelper.media_from_track (get_uri(), added);
            
            medias.set(added, on_ipod);
            if(added.mediatype == GPod.MediaType.AUDIO)
                this.songs.set(added, on_ipod);
            else if(added.mediatype == GPod.MediaType.PODCAST)
                this.podcasts.set(added, on_ipod);
            else if(added.mediatype == GPod.MediaType.AUDIOBOOK)
                this.audiobooks.set(added, on_ipod);
        }
        else {
            warning("Failed to copy track %s to iPod. Removing it from database.\n", added.title);
            remove_media(added);
        }
    }
    
    /**********************************
     * Specifically only removing medias. This is different and not a part
     * of sync. This is usually called on right click -> Remove.
     *********************************/
    bool remove_medias(LinkedList<Noise.Media> list) {
        if(currently_syncing) {
            warning("Tried to add when already syncing\n");
            return false;
        }
        else if(lm.doing_file_operations()) {
            warning("Can't add. Already doing file operations\n");
            return false;
        }
        
        if (lm.start_file_operations (_("Removing from <b>%s</b>...").printf (getDisplayName ()))) {
            current_operation = _("Removing from <b>%s</b>...").printf (getDisplayName ());
            lm.lw.update_sensitivities();
            
            currently_syncing = true;
            index = 0;
            total = medias.size + 2;
            Timeout.add(500, doProgressNotificationWithTimeout);
            
            remove_medias_thread (list);
        }
        
        return true;
    }
    
    async void remove_medias_thread(LinkedList<Noise.Media> list) {
    
        Threads.add (() => {
            bool error_occurred = false;
            
            db.start_sync();
            
            ++index; // add first of 2 extra
            
            var removed = new HashMap<unowned GPod.Track, Noise.Media>();
            foreach(var e in medias.entries) {
                foreach(var m in list) {
                    if(!sync_cancelled) {
                        // If entry e is on the list to be removed, it is to be removed
                        if(m == e.value) {
                            unowned GPod.Track t = e.key;
                            
                            if(t != null) {
                                remove_media(t);
                                removed.set(t, e.value);
                            }
                        }
                    }
                }
                
                ++index;
            }
            
            medias.unset_all(removed);
            songs.unset_all(removed);
            podcasts.unset_all(removed);
            audiobooks.unset_all(removed);
            
            if(!sync_cancelled) {
                current_operation = _("Finishing sync process...");
                
                ++index; // add second of 2 extra
                try {
                    db.write();
                }
                catch(GLib.Error err) {
                    critical("Error when writing iPod database. iPod contents may be incorrect: %s\n", err.message);
                    error_occurred = true;
                    sync_cancelled = true;
                }
                
                index = total + 1;
                
                db.stop_sync();
            }
            else {
                current_operation = _("Cancelling Sync...");
                
                try {
                    db.write();
                }
                catch(Error err) {
                    critical("Error when writing iPod database. iPod contents may be incorrect: %s\n", err.message);
                }
                
                db.stop_sync();
                index = total + 1;
                sync_cancelled = false;
            }
            
            Idle.add( () => {
                currently_syncing = false;
                
                sync_finished(!sync_cancelled);
                lm.finish_file_operations();
                lm.lw.update_sensitivities();
                
                return false;
            });
        });
        
        yield;
    }
    
    void remove_media(GPod.Track t) {
        current_operation = _("Removing <b>$NAME</b> by <b>$ARTIST</b> to $DEVICE");
        current_operation = current_operation.replace ("$NAME", t.title ?? "");
        current_operation = current_operation.replace ("$ARTIST", t.artist ?? "");
        current_operation = current_operation.replace ("$DEVICE", getDisplayName() ?? "");
        /* first check if the file exists disk */
        if(t.ipod_path != null) {
            var uri = get_uri() + GPod.iTunesDB.filename_ipod2fs(t.ipod_path);
            var file = File.new_for_uri(uri);
            
            if(file.query_exists()) {
                try {
                    /* check each playlist for the song to remove */
                    if (db.playlists_number() != 0) {
                        db.playlist_mpl().remove_track(t);
                        db.playlist_podcasts().remove_track(t);
                    }
                    foreach (unowned GPod.Playlist p in db.playlists) {
                        if(p.contains_track(t));
                            p.remove_track(t);
                    }
                    foreach (unowned GPod.Playlist p in db.playlists) {
                        if(p.contains_track(t));
                            p.remove_track(t);
                    }
                    /* Remove from all stored lists */
                    medias.unset (t, null);
                    songs.unset (t, null);
                    t.remove();
                    file.delete();
                    warning ("Successfully removed music file %s from iPod Disk\n", uri);
                }
                catch(Error err) {
                    warning("Could not delete iPod File at %s. Unused file will remain on iPod: %s\n", uri, err.message);
                }
            }
            else {
                warning("File not found, could not delete iPod File at %s. File may already be deleted\n", uri);
            }
        }
        
    }
    
    void cleanup_files(GLib.File music_folder, LinkedList<string> used_uris) {
        GLib.FileInfo file_info = null;
        
        try {
            var enumerator = music_folder.enumerate_children(FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE, 0);
            while ((file_info = enumerator.next_file ()) != null) {
                var file_uri = music_folder.get_uri() + "/" + file_info.get_name();
                
                if(file_info.get_file_type() == GLib.FileType.REGULAR && !used_uris.contains(file_uri)) { /* delete it, it's unused */
                    message("Deleting unused file %s\n", file_uri);
                    var file = File.new_for_uri(file_uri);
                    file.delete();
                }
                else if(file_info.get_file_type() == GLib.FileType.REGULAR) {
                    used_uris.remove(file_uri);
                }
                else if(file_info.get_file_type() == GLib.FileType.DIRECTORY) {
                    cleanup_files(GLib.File.new_for_uri(file_uri), used_uris);
                }
            }
        }
        catch(GLib.Error err) {
            critical("Could not pre-scan music folder. Progress percentage may be off: %s\n", err.message);
        }
    }
    
    public bool doProgressNotificationWithTimeout() {
        progress_notification(current_operation.replace("&", "&amp;"), (double)((double)index)/((double)total));
        
        if(index < total && (is_syncing() || is_transferring())) {
            return true;
        }
        
        return false;
    }
    
    void sync_podcasts() {
        
    }
    
    /* should be called from thread */
    // index = 90 at this point. will go to 95
    private void sync_playlists() {
        current_operation = _("Syncing playlists");
        // first remove all playlists from db
        var all_playlists = new LinkedList<unowned GPod.Playlist>();
        foreach(unowned GPod.Playlist p in db.playlists) {
            if(!p.is_mpl() && !p.is_podcasts() && !p.is_audiobooks()) {
                all_playlists.add(p);
            }
        }
        foreach(unowned GPod.Playlist p in all_playlists) {
            p.remove();
        }
        index = 91;
        
        int sub_index = 0;
        foreach(var playlist in lm.playlists()) {
            GPod.Playlist p = iPodPlaylistHelper.get_gpod_playlist_from_playlist (playlist);
            db.playlist_add((owned)p, -1);
            
            unowned GPod.Playlist added = db.playlists.nth_data(db.playlists.length() - 1);
            foreach(var entry in medias.entries) {
                    foreach(var e in lm.media_from_playlist(playlist.rowid)) {
                        if(entry.value == e) {
                            added.add_track(entry.key, -1);
                            ++sub_index;
                            index = (int)(78.0 + (double)(7.0 * (double)((double)sub_index/(double)lm.playlists().size)));
                            break;
                        }
                    }
            }
        }
        index = 93;
        sub_index = 0;
        foreach(var smart_playlist in lm.smart_playlists()) {
            GPod.Playlist p = iPodPlaylistHelper.get_gpod_playlist_from_smart_playlist (smart_playlist);

            db.playlist_add((owned)p, -1);

            ++sub_index;
            index = (int)(85.0 + (double)(5.0 * (double)((double)sub_index/(double)lm.smart_playlists().size)));
        }
        index = 94;
        db.spl_update_live();
        index = 95;
    }
    
    public bool transfer_to_library(LinkedList<Noise.Media> tr_list) {
        if(currently_transferring) {
            warning("Tried to sync when already syncing\n");
            return false;
        }
        else if(lm.doing_file_operations()) {
            warning("Can't sync. Already doing file operations\n");
            return false;
        }
        else if(tr_list == null || tr_list.size == 0) {
            warning("No songs in transfer list\n");
            return false;
        }
        
        Gee.LinkedList<Noise.Media> medias_to_import = delete_doubles (tr_list, lm.media ());
        if(medias_to_import.is_empty) {
            warning("No songs in transfer list\n");
            return false;
        }
        message("Found %d medias to import.", medias_to_import.size);
        int total_medias = medias_to_import.size;
        
        current_operation = _("Importing <b>$NAME</b> by <b>$ARTIST</b> to library...");
        current_operation = current_operation.replace ("$NAME", (total_medias > 1) ? total_medias.to_string() : (medias_to_import.get(0)).title ?? "");
        current_operation = current_operation.replace ("$ARTIST", (total_medias > 1) ? total_medias.to_string() : (medias_to_import.get(0)).artist ?? "");
        if (lm.start_file_operations(current_operation)) {
            
            if(medias_to_import == null || medias_to_import.size == 0)
                return true;
            
            currently_transferring = true;
            transfer_cancelled = false;
            index = 0;
            total = total_medias;
            Timeout.add(500, doProgressNotificationWithTimeout);
            transfer_medias_thread (medias_to_import);
        }
        return true;
    }
    
    public bool transfer_all_to_library() {
        var songs_to_transfer = new LinkedList<Media> ();
        foreach (var m in songs.values) {
            songs_to_transfer.add (m);
        }
        return transfer_to_library(songs_to_transfer);
    }
    
    async void transfer_medias_thread (Gee.LinkedList<Noise.Media> source_library) {
        Threads.add (() => {
        
            foreach(var m in source_library) {
                if(transfer_cancelled)
                    break;
                
                Noise.Media copy = m.copy();
                if(File.new_for_uri(copy.uri).query_exists()) {
                    copy.rowid = 0;
                    copy.isTemporary = false;
                    copy.date_added = (int)time_t();
                    lm.add_media_item (copy);
                    
                    current_operation = _("Importing <b>$NAME</b> by <b>$ARTIST</b> to library...");
                    current_operation = current_operation.replace ("$NAME", copy.title ?? "");
                    current_operation = current_operation.replace ("$ARTIST", copy.artist ?? "");
                    lm.fo.update_file_hierarchy (copy, false, false);
                }
                else {
                    message ("Skipped transferring media %s. Either already in library, or has invalid file path to ipod.\n", copy.title);
                }
                
                ++index;
            }
            
            index = total + 1;
            
            Idle.add( () => {
                lm.finish_file_operations();
                lm.lw.update_sensitivities();
                currently_transferring = false;
                
                return false;
            });
        });
    }
}
