/*-
 * Copyright (c) 2018 elementary LLC. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The Noise authors hereby grant permission for non-GPL compatible
 * GStreamer plugins to be used and distributed together with GStreamer
 * and Noise. This permission is above and beyond the permissions granted
 * by the GPL license by which Noise is covered. If you modify this code
 * you may extend this exception to your version of the code, but you are not
 * obligated to do so. If you do not wish to do so, delete this exception
 * statement from your version.
 */

public class Noise.MediaMenu : Gtk.Menu {
    public 

    Gtk.Menu media_action_menu;
    Gtk.MenuItem media_edit_media;
    Gtk.MenuItem media_file_browse;
    Gtk.MenuItem media_menu_contractor_entry; // make menu on fly
    Gtk.MenuItem media_menu_queue;
    Gtk.MenuItem media_menu_add_to_playlist; // make menu on fly
    Granite.Widgets.RatingMenuItem media_rate_media;
    Gtk.MenuItem media_remove;
    Gtk.MenuItem import_to_library;
    Gtk.MenuItem media_scroll_to_current;

    public MediaMenu () {

    }

    construct {

    }
}
