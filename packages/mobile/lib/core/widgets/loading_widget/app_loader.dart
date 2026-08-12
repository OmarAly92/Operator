import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';

class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.isCentered = false, this.strokeWidth = 4})
    : isPagination = false;

  const AppLoader.center({super.key, this.strokeWidth = 4})
    : isCentered = true,
      isPagination = false;

  const AppLoader.pagination({super.key, this.strokeWidth = 4})
    : isCentered = true,
      isPagination = true;

  final bool isCentered;
  final bool isPagination;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (isPagination) {
      return const CupertinoActivityIndicator();
    }
    if (isCentered) {
      return Center(
        child: CircularProgressIndicator(
          color: context.skin.accent,
          strokeWidth: strokeWidth,
        ),
      );
    }
    return CircularProgressIndicator(
      color: context.skin.accent,
      strokeWidth: strokeWidth,
    );
  }
}
