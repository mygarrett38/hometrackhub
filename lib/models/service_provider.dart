import 'package:flutter/material.dart';

import 'service_type.dart';

/// A local business that does home maintenance, as listed on the Nearby
/// services screen.
class ServiceProvider {
  const ServiceProvider({
    required this.id,
    required this.name,
    required this.services,
    required this.address,
    this.city,
    this.rating,
    this.ratingCount = 0,
    this.distanceMiles,
    this.hours,
    this.photo,
    this.photoCredits = const [],
    this.mapsLink,
    this.phone,
    this.website,
  });

  final String id;
  final String name;

  /// What the business does, its main service first. Never empty.
  final List<ServiceType> services;

  final String address;

  /// The city and state the business is in, such as "Springfield, IL".
  /// `null` when it isn't known.
  final String? city;

  /// The average review, from 1 to 5 stars. `null` when the business has no
  /// reviews yet.
  final double? rating;

  /// How many reviews [rating] is the average of.
  final int ratingCount;

  /// How far the business is from the user. `null` when the user's location
  /// isn't known.
  final double? distanceMiles;

  /// When the business is open on each day of the week, keyed by
  /// [DateTime.weekday]. It's closed on any day that's missing. `null` when
  /// its opening hours aren't known.
  final Map<int, DayHours>? hours;

  /// A picture that identifies the business, such as its logo or a photo
  /// of its shop or work. `null` when it has none.
  final ImageProvider? photo;

  /// The people who took [photo], who must be credited wherever it's shown
  /// large enough to credit them.
  final List<PhotoCredit> photoCredits;

  /// The business's page on Google Maps, when it came from there.
  final Uri? mapsLink;

  final String? phone;
  final Uri? website;

  ServiceType get mainService => services.first;

  /// The business's hours on the day of the week [time] falls on, or `null`
  /// if it's closed that day or its hours aren't known.
  DayHours? hoursOn(DateTime time) => hours?[time.weekday];

  /// Whether the business is open at [time], or `null` if its hours aren't
  /// known.
  bool? isOpenAt(DateTime time) {
    if (hours == null) return null;
    return hoursOn(time)?.isOpenAt(TimeOfDay.fromDateTime(time)) ?? false;
  }
}

/// Who took a business's photo, and a link to their profile.
class PhotoCredit {
  const PhotoCredit(this.name, [this.link]);

  final String name;
  final Uri? link;
}

/// When a business opens and closes on one day of the week.
class DayHours {
  const DayHours(this.opens, this.closes) : allDay = false;

  /// Open all day and night.
  const DayHours.allDay()
    : opens = const TimeOfDay(hour: 0, minute: 0),
      closes = const TimeOfDay(hour: 0, minute: 0),
      allDay = true;

  final TimeOfDay opens;

  /// When the business closes. At or before [opens] means it closes after
  /// midnight.
  final TimeOfDay closes;

  final bool allDay;

  /// Whether the business is open at [time] on this day.
  ///
  /// For a business that closes after midnight, the early hours count as
  /// open on every day it has hours, rather than only the morning after.
  bool isOpenAt(TimeOfDay time) {
    if (allDay) return true;
    final now = _minutes(time);
    final open = _minutes(opens);
    final close = _minutes(closes);
    return close > open
        ? now >= open && now < close
        : now >= open || now < close;
  }

  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;
}
