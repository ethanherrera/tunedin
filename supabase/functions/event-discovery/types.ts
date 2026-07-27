export interface DiscoveryLocation {
  city: string;
  stateCode: string | null;
  countryCode: string;
}

export interface DiscoverRequest {
  operation: "discover";
  location: DiscoveryLocation;
  startDateTime: string;
  endDateTime: string;
  genre: string | null;
  page: number;
}

export interface ResolveRequest {
  operation: "resolve";
  eventId: string;
}

export type DiscoveryRequest = DiscoverRequest | ResolveRequest;

export interface DiscoveryArtist {
  id: string;
  name: string;
  url: string | null;
}

export interface DiscoveryVenue {
  id: string;
  name: string;
  url: string | null;
  address: string | null;
  city: string;
  stateCode: string | null;
  countryCode: string;
  latitude: string | null;
  longitude: string | null;
}

export interface DiscoveryCandidate {
  id: string;
  name: string;
  localDate: string;
  localTime: string | null;
  dateTime: string | null;
  timeZone: string | null;
  status: "active" | "cancelled" | "postponed";
  venue: DiscoveryVenue;
  artists: DiscoveryArtist[];
  genre: string | null;
  imageURL: string | null;
  ticketURL: string;
}

export interface DiscoverResponse {
  operation: "discover";
  location: DiscoveryLocation;
  page: number;
  hasMore: boolean;
  events: DiscoveryCandidate[];
}

export interface ResolveResponse {
  operation: "resolve";
  eventId: string;
  catalogEventId: string;
}

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };

export interface AuthenticatedProfile {
  id: string;
}
