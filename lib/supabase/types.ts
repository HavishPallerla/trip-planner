export type TripParticipantStatus = 'invited' | 'confirmed' | 'declined';
export type TripItemType = 'hostel' | 'flight' | 'excursion' | 'custom';
export type TripItemConfirmationStatus = 'upvote' | 'in' | 'out';

export interface Profile {
  id: string;
  email: string;
  display_name: string;
  ics_token: string;
  created_at: string;
}

export interface Trip {
  id: string;
  name: string;
  destination_city: string;
  start_date: string;
  end_date: string;
  color: string;
  created_by: string;
  created_at: string;
}

export interface TripParticipant {
  trip_id: string;
  user_id: string;
  status: TripParticipantStatus;
  joined_at: string;
}

export interface TripItem {
  id: string;
  trip_id: string;
  type: TripItemType;
  title: string;
  details: Record<string, unknown>;
  cost: number;
  currency: string;
  proposed_by: string;
  created_at: string;
}

export interface TripItemConfirmation {
  trip_item_id: string;
  user_id: string;
  status: TripItemConfirmationStatus;
  created_at: string;
}
