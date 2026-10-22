import { Controller } from "@hotwired/stimulus"
import { Map } from '../maps/map'

// Connects to data-controller="map"
export default class extends Controller {
  static targets = [ "map", "sidebar" ]
  static values = {
    apiKey: String,
    mapId: String,
    config: Object,
    markers: Array,
    static: Boolean
  }

  #map = null

  connect() {
    this.#map = new Map({
      apiKey: this.apiKeyValue,
      mapId: this.mapIdValue,
      config: this.configValue,
      initialMarkers: this._markersForPage(this.markersValue).map(this._markerData),
      boundsOffsetX: this._sidebarWidth.bind(this),
      mapElement: this.mapTarget
    })
  }

  update(event) {
    this._updateFromUrl({
      url: event.target.dataset.url,
      callback: this._updateWithVenues.bind(this)
    })
  }

  _updateWithVenues(venues) {
    const markersData = this._markersForPage(venues).map(this._markerData)
    this.#map.updateMarkers(markersData)
  }

  // On an exported page the query string is the only place the venue can come
  // from, because the HTML was rendered once at export time and cannot have
  // known which venue the visitor was arriving for.
  _markersForPage(venues) {
    const venueId = Number(new URLSearchParams(window.location.search).get('venue_id'))

    if (!this.staticValue) { return venues }

    return venues.map(venue => ({ ...venue, highlighted: venue.id === venueId }))
  }

  _updateFromUrl({url, callback}) {
    fetch(url)
      .then(response => {
        return response.json()
      })
      .then(data => {
        callback(data.markers)
      })
  }

  _markerData(venue) {
    return {
      lat: venue.position.lat,
      lng: venue.position.lng,
      title: venue.title,
      url: venue.url,
      highlighted: venue.highlighted,
      content: venue.infoWindowContent
    }
  }

  _sidebarWidth() {
    if (this._sidebarVisible()) {
      return this.sidebarTarget.offsetWidth
    } else {
      return 0;
    }
  }

  _sidebarVisible() {
    const style = window.getComputedStyle(this.sidebarTarget);
    return style.display !== 'none'
  }
}
