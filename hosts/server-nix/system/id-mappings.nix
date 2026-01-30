{
  users.users."root" = {
    subUidRanges = [
      {
        startUid = 1000;
        count = 11;
      } # Covers 1000-1010
      {
        startUid = 100000;
        count = 1000000;
      } # Allow 1 million mappings
    ];
    subGidRanges = [
      {
        startGid = 1000;
        count = 11;
      } # Covers 1000-1010
      {
        startGid = 100000;
        count = 1000000;
      } # Allow 1 million mappings
    ];
  };
}
