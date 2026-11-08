import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/service_provider.dart';
import '../../../models/service_sort.dart';
import '../../../models/service_type.dart';
import '../../../services/location_service.dart';
import '../../../services/nearby_services_client.dart';
import '../../../state/nearby_services_controller.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/screen_padding.dart';
import '../settings/nearby_services_settings_screen.dart';

/// Search for home maintenance businesses near the user, such as plumbers
/// or HVAC technicians.
///
/// The user can search by name, pick one kind of service, show only
/// businesses that are open or well rated, and sort the results. Tapping a
/// business shows its details, with buttons to call it, open its website or
/// get directions.
///
/// Where to search around and the order the results start in come from the
/// Nearby services settings.
class NearbyServicesScreen extends StatelessWidget {
  const NearbyServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final settings = context.read<SettingsController>();
        final location = context.read<LocationService>();
        return NearbyServicesController(
          context.read<NearbyServicesClient>(),
          initialSort: settings.settings.nearbySort,
          // Reads the settings when it's called, so changes made from the
          // error message's settings button are used.
          locate: () => searchAreaFor(settings.settings, location),
        )..search();
      },
      child: const _NearbyServicesView(),
    );
  }
}

class _NearbyServicesView extends StatefulWidget {
  const _NearbyServicesView();

  @override
  State<_NearbyServicesView> createState() => _NearbyServicesViewState();
}

class _NearbyServicesViewState extends State<_NearbyServicesView> {
  final _search = TextEditingController();

  /// Whether the service, rating and sort choices are shown under the top
  /// bar. They're hidden at first to leave more room for the results.
  bool _filtersOpen = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NearbyServicesController>();
    // Counted on the filters button, so the user can tell the results are
    // narrowed down while the filters are hidden.
    final activeFilters = [
      controller.service != null,
      controller.minRating != null,
      controller.openNowOnly,
    ].where((active) => active).length;
    // With a back button the search bar sits right next to it.
    final hasBackButton =
        ModalRoute.of(context)?.impliesAppBarDismissal ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: hasBackButton ? 0 : 16,
        title: SearchBar(
          controller: _search,
          hintText: 'Search nearby services',
          constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
          elevation: const WidgetStatePropertyAll(0),
          leading: const Icon(Icons.search),
          trailing: [
            if (_search.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _search.clear();
                  setState(() {});
                  controller.setQuery('');
                },
              ),
          ],
          textInputAction: TextInputAction.search,
          onChanged: (text) {
            // Shows or hides the clear button.
            setState(() {});
            controller.setQuery(text);
          },
          onSubmitted: (_) => controller.searchNow(),
        ),
        actions: [
          IconButton(
            tooltip: _filtersOpen ? 'Hide filters' : 'Show filters',
            isSelected: _filtersOpen,
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            icon: Badge(
              isLabelVisible: activeFilters > 0,
              label: Text('$activeFilters'),
              child: const Icon(Icons.tune),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Slides open and closed, unless the device asks for reduced
          // motion.
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _filtersOpen
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 4),
                      _ServiceChips(
                        selected: controller.service,
                        onSelected: controller.setService,
                      ),
                      _FilterRow(controller: controller),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          // Keeps its height when hidden, so the list doesn't jump.
          SizedBox(
            height: 4,
            child: controller.loading && controller.searched
                ? const LinearProgressIndicator()
                : null,
          ),
          Expanded(child: _results(controller)),
        ],
      ),
    );
  }

  Widget _results(NearbyServicesController controller) {
    if (!controller.searched) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = controller.error;
    if (error != null) {
      return _Message(
        icon: controller.errorFixInSettings
            ? Icons.location_off_outlined
            : Icons.cloud_off_outlined,
        text: error,
        action: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: controller.relocate,
              child: const Text('Try again'),
            ),
            if (controller.errorFixInSettings)
              OutlinedButton(
                onPressed: () => _openSettings(controller),
                child: const Text('Nearby services settings'),
              ),
          ],
        ),
      );
    }

    final providers = controller.providers;
    final hidden = controller.hiddenCount;
    if (providers.isEmpty) {
      return hidden > 0
          ? _Message(
              icon: Icons.filter_alt_off_outlined,
              text:
                  'No businesses match your filters. '
                  '${_businesses(hidden)} found are hidden by them.',
              action: FilledButton.tonal(
                onPressed: controller.clearFilters,
                child: const Text('Clear filters'),
              ),
            )
          : const _Message(
              icon: Icons.search_off,
              text:
                  'No businesses found. Try searching for something else or '
                  'picking a different service.',
            );
    }

    return ListView(
      padding: screenPadding(context).copyWith(top: 8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (controller.isSample) const _SampleNotice(),
        for (final provider in providers)
          _ProviderCard(
            key: ValueKey(provider.id),
            provider: provider,
            onTap: () => _showDetails(provider, controller.now),
          ),
        if (!controller.isSample) const _GoogleMapsCredit(),
      ],
    );
  }

  /// Opens the Nearby services settings, then searches again in case the
  /// user changed where to search.
  Future<void> _openSettings(NearbyServicesController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NearbyServicesSettingsScreen(),
      ),
    );
    if (mounted) await controller.relocate();
  }

  void _showDetails(ServiceProvider provider, DateTime now) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProviderDetails(provider: provider, now: now),
    );
  }

  static String _businesses(int count) =>
      '$count ${count == 1 ? 'business' : 'businesses'}';
}

/// A row of chips, scrolling sideways, for picking one kind of service, or
/// "All" for any.
class _ServiceChips extends StatelessWidget {
  const _ServiceChips({required this.selected, required this.onSelected});

  final ServiceType? selected;
  final ValueChanged<ServiceType?> onSelected;

  @override
  Widget build(BuildContext context) {
    final choices = <ServiceType?>[null, ...ServiceType.values];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: choices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final service = choices[index];
          return ChoiceChip(
            avatar: service == null ? null : Icon(service.icon),
            label: Text(service?.label ?? 'All'),
            selected: service == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(service),
          );
        },
      ),
    );
  }
}

/// The open now and minimum rating filters, and the sort order.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.controller});

  final NearbyServicesController controller;

  @override
  Widget build(BuildContext context) {
    final minRating = controller.minRating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Open now'),
            selected: controller.openNowOnly,
            onSelected: controller.setOpenNowOnly,
          ),
          const SizedBox(width: 8),
          _MenuChip(
            label: minRating == null
                ? 'Any rating'
                : '${minRating.toStringAsFixed(1)}+ stars',
            icon: Icons.star_outline,
            active: minRating != null,
            items: [
              for (final rating in [
                null,
                ...NearbyServicesController.minRatingChoices,
              ])
                _MenuChoice(
                  label: rating == null
                      ? 'Any rating'
                      : '${rating.toStringAsFixed(1)} stars and up',
                  selected: rating == minRating,
                  onPressed: () => controller.setMinRating(rating),
                ),
            ],
          ),
          const Spacer(),
          MenuAnchor(
            menuChildren: [
              for (final sort in ServiceSort.values)
                _MenuChoice(
                  label: sort.label,
                  selected: sort == controller.sort,
                  onPressed: () => controller.setSort(sort),
                ),
            ],
            builder: (context, menu, _) => TextButton.icon(
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              icon: const Icon(Icons.sort),
              label: Text(controller.sort.label),
            ),
          ),
        ],
      ),
    );
  }
}

/// A filter chip that opens a menu of [items] for choosing its value.
/// [active] highlights it when the filter is hiding anything.
class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.items,
  });

  final String label;
  final IconData icon;
  final bool active;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: items,
      builder: (context, menu, _) => FilterChip(
        avatar: Icon(icon),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label), const Icon(Icons.arrow_drop_down, size: 18)],
        ),
        selected: active,
        showCheckmark: false,
        onSelected: (_) => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// One choice in a filter or sort menu, with a check by the chosen one.
class _MenuChoice extends StatelessWidget {
  const _MenuChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      leadingIcon: selected
          ? const Icon(Icons.check)
          : const SizedBox(width: 24),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Explains that the businesses listed are made up, while the screen isn't
/// connected to real listings.
class _SampleNotice extends StatelessWidget {
  const _SampleNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "These are sample businesses. Real listings near you aren't "
                'connected yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A business in the results: its picture on the left, fading out toward
/// its name and city, and its rating on the right.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({super.key, required this.provider, required this.onTap});

  final ServiceProvider provider;
  final VoidCallback onTap;

  /// How far into the card the picture reaches. It has faded out
  /// completely by here.
  static const photoWidth = 80.0;

  /// The space between where the picture has faded out and where the name
  /// and hours start.
  static const photoGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: photoWidth,
              child: _FadingPhoto(provider: provider),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                photoWidth + photoGap,
                16,
                16,
                16,
              ),
              child: Row(
                children: [
                  // Always two lines for the name and one for the city, even
                  // when they're shorter or missing, so every card is the
                  // same height. Longer names end in "...".
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            Visibility.maintain(
                              visible: false,
                              child: Text(
                                'A\nA',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              provider.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // A space keeps the line's height when the city
                          // isn't known.
                          provider.city ?? ' ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CompactRating(provider: provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A business's picture, as tall as its card: shown in full on the left,
/// then fading out evenly toward the right until it's gone. While the
/// picture loads, or when there isn't one or it can't be loaded, the
/// business's main service icon is shown on a tint instead.
class _FadingPhoto extends StatelessWidget {
  const _FadingPhoto({required this.provider});

  final ServiceProvider provider;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photo = provider.photo;
    final placeholder = ColoredBox(
      color: colors.secondaryContainer,
      child: Align(
        // In the middle of the part that isn't faded.
        alignment: const Alignment(-0.45, 0),
        child: Icon(
          provider.mainService.icon,
          size: 36,
          color: colors.onSecondaryContainer,
        ),
      ),
    );

    return ShaderMask(
      // Keeps the picture only where the gradient is opaque.
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.black, Colors.black, Colors.transparent],
        stops: [0, 0.35, 1],
      ).createShader(bounds),
      child: photo == null
          ? placeholder
          : Image(
              image: photo,
              fit: BoxFit.cover,
              // The card already reads out the business's name.
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, _) =>
                  frame == null ? placeholder : child,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }
}

/// A business's rating for its card in the results: one star and the
/// average rating, with the number of reviews under them. Nothing for a
/// business with no reviews yet.
/// Read aloud as one phrase, such as "Rated 4.5 out of 5 from 120 reviews".
class _CompactRating extends StatelessWidget {
  const _CompactRating({required this.provider});

  final ServiceProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final rating = provider.rating;
    if (rating == null) return const SizedBox.shrink();

    final reviews = _reviews(provider.ratingCount);
    return Semantics(
      label: _ratingLabel(rating, reviews),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, size: 24, color: theme.colorScheme.tertiary),
              const SizedBox(width: 2),
              Text(
                rating.toStringAsFixed(1),
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(reviews, style: muted),
        ],
      ),
    );
  }
}

/// A business's stars, average rating and number of reviews, for its
/// details, or "No reviews yet". Read aloud as one phrase, such as "Rated
/// 4.5 out of 5 from 120 reviews".
class _Rating extends StatelessWidget {
  const _Rating({required this.provider});

  final ServiceProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final rating = provider.rating;
    if (rating == null) return Text('No reviews yet', style: muted);

    final count = provider.ratingCount;
    return Semantics(
      label: _ratingLabel(rating, _reviews(count)),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var star = 0; star < 5; star++)
            Icon(
              // Rounded to the nearest half star.
              switch (rating - star) {
                >= 0.75 => Icons.star,
                >= 0.25 => Icons.star_half,
                _ => Icons.star_border,
              },
              size: 18,
              color: theme.colorScheme.tertiary,
            ),
          const SizedBox(width: 6),
          Text(rating.toStringAsFixed(1), style: theme.textTheme.labelLarge),
          Text(' ($count)', style: muted),
        ],
      ),
    );
  }
}

/// Whether a business is open at [now], and its hours that day only, on
/// one line: "Open now · 8 AM – 5 PM", "Closed · 8 AM – 5 PM",
/// "Closed today" or "Open 24 hours". Only for a business whose hours are
/// known.
class _OpenStatus extends StatelessWidget {
  const _OpenStatus({required this.provider, required this.now});

  final ServiceProvider provider;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = provider.isOpenAt(now) ?? false;
    final (status, hours) = switch (provider.hoursOn(now)) {
      null => ('Closed today', null),
      DayHours(allDay: true) => ('Open 24 hours', null),
      final today => (
        open ? 'Open now' : 'Closed',
        '${_time(context, today.opens)} – ${_time(context, today.closes)}',
      ),
    };
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: status,
            style: theme.textTheme.labelLarge?.copyWith(
              color: open ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
          ),
          if (hours != null)
            TextSpan(
              text: ' · $hours',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// A time of day in the device's 12 or 24-hour format. On the hour, a
  /// 12-hour time leaves out the minutes, such as "8 AM", to keep the line
  /// short.
  static String _time(BuildContext context, TimeOfDay time) {
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final text = MaterialLocalizations.of(context)
        .formatTimeOfDay(time, alwaysUse24HourFormat: use24Hour);
    return use24Hour || time.minute != 0 ? text : text.replaceFirst(':00', '');
  }
}

/// The details of one business, in a sheet that slides up from the bottom,
/// with buttons to call it, open its website, or get directions in a maps
/// app.
class _ProviderDetails extends StatelessWidget {
  const _ProviderDetails({required this.provider, required this.now});

  final ServiceProvider provider;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = provider.phone;
    final website = provider.website;

    return SingleChildScrollView(
      padding: screenPadding(context).copyWith(top: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Google lets its photos go uncredited on the small cards, as long
          // as they're shown larger with the credit here.
          if (provider.photo case final photo?
              when provider.photoCredits.isNotEmpty) ...[
            _CreditedPhoto(photo: photo, credits: provider.photoCredits),
            const SizedBox(height: 16),
          ],
          Text(provider.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          _Rating(provider: provider),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final service in provider.services)
                Chip(avatar: Icon(service.icon), label: Text(service.label)),
            ],
          ),
          const SizedBox(height: 8),
          _DetailRow(icon: Icons.place_outlined, text: provider.address),
          if (provider.distanceMiles case final miles?)
            _DetailRow(
              icon: Icons.near_me_outlined,
              text: '${_miles(miles)} away',
            ),
          if (provider.hours != null)
            _DetailRow(
              icon: Icons.schedule,
              child: _OpenStatus(provider: provider, now: now),
            ),
          if (phone != null)
            _DetailRow(icon: Icons.phone_outlined, text: phone),
          const SizedBox(height: 16),
          Row(
            children: [
              if (phone != null)
                _ActionButton(
                  icon: Icons.call,
                  label: 'Call',
                  filled: true,
                  onPressed: () => _open(
                    context,
                    Uri(
                      scheme: 'tel',
                      path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                    ),
                    'the phone app',
                  ),
                ),
              if (website != null)
                _ActionButton(
                  icon: Icons.language,
                  label: 'Website',
                  onPressed: () => _open(context, website, 'the website'),
                ),
              _ActionButton(
                icon: Icons.directions_outlined,
                label: 'Directions',
                onPressed: () => _open(
                  context,
                  // The business's own Google Maps page when there is one.
                  provider.mapsLink ??
                      Uri.https('www.google.com', '/maps/search/', {
                        'api': '1',
                        'query': '${provider.name}, ${provider.address}',
                      }),
                  'directions',
                ),
              ),
            ],
          ),
          if (provider.mapsLink != null) const _GoogleMapsCredit(),
        ],
      ),
    );
  }

  /// Opens [uri] in another app, or says that [what] couldn't be opened.
  static Future<void> _open(BuildContext context, Uri uri, String what) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't open $what on this device.")),
      );
    }
  }
}

/// A business's photo, as wide as its details, with who took it under it.
/// Tapping the name opens their profile.
class _CreditedPhoto extends StatelessWidget {
  const _CreditedPhoto({required this.photo, required this.credits});

  final ImageProvider photo;
  final List<PhotoCredit> credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = credits.first.link;
    final names = credits.map((credit) => credit.name).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image(
              image: photo,
              fit: BoxFit.cover,
              semanticLabel: 'Photo of the business',
              errorBuilder: (context, error, stackTrace) =>
                  ColoredBox(color: theme.colorScheme.secondaryContainer),
            ),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: link == null
              ? null
              : () => _ProviderDetails._open(context, link, 'the profile'),
          child: Text('Photo: $names', style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Google's logo at the bottom right, saying the results came from Google
/// Maps. Google requires it wherever its places are shown without a Google
/// map, unchanged, 16 to 19 points tall, with clear space around it, and
/// read aloud as "Google Maps".
///
/// The plain logo is for plain backgrounds like these: dark gray in light
/// mode and white in dark mode, so it stands out from the background.
class _GoogleMapsCredit extends StatelessWidget {
  const _GoogleMapsCredit();

  static const logoHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        // The least clear space Google allows around the logo.
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
        child: Image.asset(
          dark
              ? 'assets/images/google_maps/google_maps_logo_white.png'
              : 'assets/images/google_maps/google_maps_logo_dark_gray.png',
          height: logoHeight,
          semanticLabel: 'Google Maps',
        ),
      ),
    );
  }
}

/// A line of detail about a business, with an icon: [text], or [child] in
/// its place.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, this.text, this.child})
    : assert((text == null) != (child == null));

  final IconData icon;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: child ?? Text(text!, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

/// One of the evenly spaced buttons under a business's details, with its
/// label under its icon. [filled] is for the main action.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: filled
            ? FilledButton(
                style: FilledButton.styleFrom(shape: shape),
                onPressed: onPressed,
                child: content,
              )
            : FilledButton.tonal(
                style: FilledButton.styleFrom(shape: shape),
                onPressed: onPressed,
                child: content,
              ),
      ),
    );
  }
}

/// A centered message with an icon, and optionally a button under it, for
/// when there are no results to show.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action case final action?) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// A distance such as "2.4 mi".
String _miles(double miles) => '${miles.toStringAsFixed(1)} mi';

/// A number of reviews such as "120 reviews".
String _reviews(int count) => '$count ${count == 1 ? 'review' : 'reviews'}';

/// How a rating is read aloud, such as "Rated 4.5 out of 5 from 120
/// reviews".
String _ratingLabel(double rating, String reviews) =>
    'Rated ${rating.toStringAsFixed(1)} out of 5 from $reviews';
